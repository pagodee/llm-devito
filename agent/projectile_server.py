#!/usr/bin/env python3
"""Servidor MCP mínimo que dá ao agente uma ferramenta: simulate_projectile.

MCP (Model Context Protocol) via stdio é JSON-RPC 2.0, um objeto JSON por
linha: o harness escreve pedidos no nosso stdin, e respondemos no stdout.
Só a biblioteca padrão do Python é usada, então não há nada para instalar.

Regra de servidores stdio: o stdout carrega SOMENTE mensagens do protocolo.
Qualquer coisa para humanos (prints de depuração) vai para o stderr, ou
corrompe o protocolo.

A física: um projétil esférico com arrasto quadrático,
    dv/dt = -g ŷ - k |v| v,   com  k = rho * Cd * A / (2 m),  A = pi d^2 / 4.
Com arrasto não existe fórmula fechada para o alcance, por isso o agente
precisa da ferramenta. Sem arrasto existe (a parábola), e ela é usada para
conferir o integrador numérico.
"""
import json
import math
import sys

SERVER_INFO = {"name": "physics", "version": "0.2.0"}

# Revisões do protocolo que este servidor fala (handshake clássico "initialize")
SUPPORTED_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

INSTRUCTIONS = (
    "Numerical physics experiments. Use simulate_projectile to get ranges, "
    "flight times and heights of projectiles with air resistance instead of "
    "estimating numbers by hand."
)

# O que o modelo vê: nome, descrição e o JSON Schema dos argumentos. O modelo
# decide quando e como chamar a ferramenta só a partir deste texto, então a
# descrição faz parte do projeto do agente, não é só documentação. Fica em
# inglês porque modelos pequenos seguem instruções em inglês com mais precisão.
PROJECTILE_TOOL = {
    "name": "simulate_projectile",
    "description": (
        "Numerically integrate the 2D flight of a spherical projectile WITH "
        "quadratic air drag: dv/dt = -g y_hat - k |v| v, k = rho Cd A / (2 m), "
        "launched from the given height until it hits the ground (y = 0). Uses "
        "4th-order Runge-Kutta. Returns range, flight time, maximum height and "
        "impact speed with drag; the exact no-drag (vacuum) values from the "
        "analytic parabola; the percentage reduction of the range caused by "
        "drag; the terminal speed; two accuracy checks (integrator_check: the "
        "same integrator without drag vs the exact parabola; convergence_check: "
        "the drag simulation repeated with half the time step); and a short "
        "table of samples (t, x, y, speed). The time step is reduced "
        "automatically where needed for accuracy (dt_used_s gives its range)."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "speed_m_s": {"type": "number", "description": "Launch speed in m/s (> 0)."},
            "angle_deg": {"type": "number", "description": "Launch angle above the horizontal, in degrees, 0 < angle < 90."},
            "mass_kg": {"type": "number", "description": "Projectile mass in kg (> 0)."},
            "diameter_m": {"type": "number", "description": "Projectile diameter in m (> 0)."},
            "drag_coefficient": {"type": "number", "description": "Drag coefficient Cd (>= 0). Default 0.47 (smooth sphere)."},
            "air_density_kg_m3": {"type": "number", "description": "Air density in kg/m^3 (>= 0). Default 1.225 (sea level, 15 C)."},
            "height_m": {"type": "number", "description": "Launch height above the ground in m (>= 0). Default 0."},
            "g_m_s2": {"type": "number", "description": "Gravitational acceleration in m/s^2 (> 0). Default 9.81."},
            "dt_s": {"type": "number", "description": "Maximum time step in s (> 0). Default 0.001."},
        },
        "required": ["speed_m_s", "angle_deg", "mass_kg", "diameter_m"],
    },
}

MAX_STEPS = 2_000_000
N_SAMPLES = 20

# Limites do passo de tempo. O RK4 só é preciso (e estável) se cada passo for
# pequeno perto das escalas do problema:
#   - voo: pelo menos ~1000 passos no tempo de voo sem arrasto;
#   - arrasto: em um passo, o arrasto muda a velocidade no máximo ~1 %
#     (k |v| dt <= 0.01). Com arrasto forte, um passo maior dá resultados sem
#     sentido, como alcance zero. Como |v| muda durante o voo, esse limite é
#     recalculado a cada passo: o passo encolhe quando o objeto está rápido e
#     volta a crescer quando ele desacelera.
DRAG_STEP_FRACTION = 0.01
MIN_STEPS_PER_FLIGHT = 1000


def integrate(vx, vy, height, k, g, dt_max, drag_fraction=DRAG_STEP_FRACTION):
    """Integra com RK4 até o projétil tocar o chão.

    Devolve o voo, as amostras (t, x, y, |v|) e o menor passo usado."""

    def accel(vx, vy):
        speed = math.hypot(vx, vy)
        return -k * speed * vx, -g - k * speed * vy

    x, y, t = 0.0, float(height), 0.0
    max_y = y
    min_dt = dt_max
    samples = [(t, x, y, math.hypot(vx, vy))]
    sample_every = 1
    for i in range(1, MAX_STEPS + 1):
        dt = dt_max
        speed = math.hypot(vx, vy)
        if k > 0 and speed > 0:
            dt = min(dt, drag_fraction / (k * speed))
        min_dt = min(min_dt, dt)
        # RK4 clássico para o sistema (x' = vx, y' = vy, vx' = ax, vy' = ay)
        a1x, a1y = accel(vx, vy)
        a2x, a2y = accel(vx + dt / 2 * a1x, vy + dt / 2 * a1y)
        a3x, a3y = accel(vx + dt / 2 * a2x, vy + dt / 2 * a2y)
        a4x, a4y = accel(vx + dt * a3x, vy + dt * a3y)
        new_x = x + dt / 6 * (vx + 2 * (vx + dt / 2 * a1x) + 2 * (vx + dt / 2 * a2x) + (vx + dt * a3x))
        new_y = y + dt / 6 * (vy + 2 * (vy + dt / 2 * a1y) + 2 * (vy + dt / 2 * a2y) + (vy + dt * a3y))
        new_vx = vx + dt / 6 * (a1x + 2 * a2x + 2 * a3x + a4x)
        new_vy = vy + dt / 6 * (a1y + 2 * a2y + 2 * a3y + a4y)

        if new_y < 0:  # tocou o chão neste passo: interpola o instante exato
            f = y / (y - new_y)
            land_x = x + f * (new_x - x)
            land_t = t + f * dt
            impact = math.hypot(vx + f * (new_vx - vx), vy + f * (new_vy - vy))
            samples.append((land_t, land_x, 0.0, impact))
            return {"range_m": land_x, "flight_time_s": land_t,
                    "max_height_m": max_y, "impact_speed_m_s": impact}, samples, min_dt

        x, y, vx, vy, t = new_x, new_y, new_vx, new_vy, t + dt
        max_y = max(max_y, y)
        if i % sample_every == 0:
            samples.append((t, x, y, math.hypot(vx, vy)))
            # Mantém a tabela curta sem saber de antemão quantos passos o voo
            # terá: quando passa do dobro do desejado, descarta metade das
            # amostras e passa a amostrar com metade da frequência.
            if len(samples) > 2 * N_SAMPLES:
                samples = samples[::2]
                sample_every *= 2
    raise ValueError(f"the projectile did not land within {MAX_STEPS} steps; "
                     "the flight is too long for the required time step")


def simulate_projectile(speed_m_s, angle_deg, mass_kg, diameter_m, drag_coefficient=0.47,
                        air_density_kg_m3=1.225, height_m=0.0, g_m_s2=9.81, dt_s=0.001):
    inputs = {"speed_m_s": speed_m_s, "angle_deg": angle_deg, "mass_kg": mass_kg,
              "diameter_m": diameter_m, "drag_coefficient": drag_coefficient,
              "air_density_kg_m3": air_density_kg_m3, "height_m": height_m,
              "g_m_s2": g_m_s2, "dt_s": dt_s}
    for name, value in inputs.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise ValueError(f"{name} must be a finite number")
    v0, m, d = float(speed_m_s), float(mass_kg), float(diameter_m)
    cd, rho, h = float(drag_coefficient), float(air_density_kg_m3), float(height_m)
    g, dt_max = float(g_m_s2), float(dt_s)
    if v0 <= 0 or m <= 0 or d <= 0 or g <= 0 or dt_max <= 0:
        raise ValueError("speed_m_s, mass_kg, diameter_m, g_m_s2 and dt_s must be > 0")
    if cd < 0 or rho < 0 or h < 0:
        raise ValueError("drag_coefficient, air_density_kg_m3 and height_m must be >= 0")
    if not 0 < angle_deg < 90:
        raise ValueError("angle_deg must be strictly between 0 and 90")

    theta = math.radians(angle_deg)
    vx0, vy0 = v0 * math.cos(theta), v0 * math.sin(theta)
    k = rho * cd * (math.pi * d * d / 4) / (2 * m)

    # Solução exata sem arrasto (parábola), a partir da altura h
    t_vac = (vy0 + math.sqrt(vy0 * vy0 + 2 * g * h)) / g
    vacuum = {"range_m": vx0 * t_vac, "flight_time_s": t_vac,
              "max_height_m": h + vy0 * vy0 / (2 * g),
              "impact_speed_m_s": math.sqrt(v0 * v0 + 2 * g * h)}
    if not vacuum["range_m"] > 0:
        raise ValueError("the inputs are too small to simulate (the no-drag range is zero)")

    # Passo máximo: o pedido, reduzido se for grande demais para o voo.
    # Dentro da integração ele ainda encolhe quando o arrasto é forte.
    dt = min(dt_max, t_vac / MIN_STEPS_PER_FLIGHT)

    drag, samples, min_dt = integrate(vx0, vy0, h, k, g, dt)
    # Conferência 1: o mesmo integrador, sem arrasto, contra a parábola exata
    vac_num, _, _ = integrate(vx0, vy0, h, 0.0, g, dt)
    integrator_error = abs(vac_num["range_m"] - vacuum["range_m"]) / vacuum["range_m"]
    # Conferência 2: a simulação com arrasto repetida com todos os passos pela
    # metade. Se o resultado quase não muda, os passos são pequenos o bastante.
    half, _, _ = integrate(vx0, vy0, h, k, g, dt / 2, DRAG_STEP_FRACTION / 2)
    convergence = abs(half["range_m"] - drag["range_m"]) / max(abs(half["range_m"]), 1e-300)

    def rounded(values):
        return {key: float(f"{val:.6g}") for key, val in values.items()}

    return {
        "inputs": inputs,
        "dt_used_s": {"max": float(f"{dt:.6g}"), "min": float(f"{min_dt:.6g}")},
        "drag_constant_k_per_m": float(f"{k:.6g}"),
        "terminal_speed_m_s": float(f"{math.sqrt(g / k):.6g}") if k > 0 else None,
        "with_drag": rounded(drag),
        "without_drag_exact": rounded(vacuum),
        "range_reduction_percent": round(100 * (1 - drag["range_m"] / vacuum["range_m"]), 4),
        "integrator_check": {
            "description": "same integrator without drag vs exact parabola: relative error of the range",
            "relative_error": float(f"{integrator_error:.3e}"),
        },
        "convergence_check": {
            "description": "drag simulation repeated with dt/2: relative change of the range",
            "relative_change": float(f"{convergence:.3e}"),
        },
        "samples": {
            "columns": ["t_s", "x_m", "y_m", "speed_m_s"],
            "rows": [[float(f"{v:.6g}") for v in row] for row in samples],
        },
    }


TOOLS = {"simulate_projectile": (PROJECTILE_TOOL, simulate_projectile)}


def handle(request):
    """Devolve a resposta JSON-RPC para um pedido (None para notificações)."""
    if not isinstance(request, dict):
        return error(None, -32600, "Invalid request: expected a JSON object")
    method, req_id = request.get("method"), request.get("id")
    params = request.get("params")
    if not isinstance(params, dict):
        params = {}
    if req_id is None:  # notificações (ex.: notifications/initialized) não têm resposta
        return None

    if method == "initialize":
        asked = params.get("protocolVersion")
        result = {
            "protocolVersion": asked if asked in SUPPORTED_VERSIONS else SUPPORTED_VERSIONS[0],
            "capabilities": {"tools": {}},
            "serverInfo": SERVER_INFO,
            "instructions": INSTRUCTIONS,
        }
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [schema for schema, _ in TOOLS.values()]}
    elif method == "tools/call":
        name, args = params.get("name"), params.get("arguments") or {}
        if name not in TOOLS:
            return error(req_id, -32602, f"Unknown tool: {name}")
        if not isinstance(args, dict):
            return error(req_id, -32602, "arguments must be a JSON object")
        try:
            output = TOOLS[name][1](**args)
            result = {"content": [{"type": "text", "text": json.dumps(output)}], "isError": False}
        except Exception as exc:  # noqa: BLE001 — qualquer falha da ferramenta volta para o modelo
            # Um erro da ferramenta volta para o modelo como resultado normal,
            # para ele ler a mensagem e tentar de novo com argumentos corrigidos.
            result = {"content": [{"type": "text", "text": f"Error: {exc}"}], "isError": True}
    else:
        # Inclui o handshake novo "server/discover": responder "método não
        # encontrado" faz o cliente voltar para o "initialize" clássico.
        return error(req_id, -32601, f"Method not found: {method}")

    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            response = error(None, -32700, f"Parse error: {exc}")
        else:
            try:
                response = handle(request)
            except Exception as exc:  # noqa: BLE001 — o servidor nunca deve morrer
                req_id = request.get("id") if isinstance(request, dict) else None
                response = error(req_id, -32603, f"Internal error: {exc}")
        if response is not None:
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
