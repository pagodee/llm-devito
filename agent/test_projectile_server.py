#!/usr/bin/env python3
"""Testa o servidor MCP SEM modelo: conversa com ele pelo protocolo, como o dsh
faria, e confere a física. Roda em segundos.

    python3 agent/test_projectile_server.py

Ou dentro da imagem, com o mesmo Python que o agente usa:

    apptainer exec --containall --bind agent:/agent:ro llm-devito.sif \\
        python3 /agent/test_projectile_server.py
"""
import json
import math
import subprocess
import sys
from pathlib import Path

SERVER = Path(__file__).with_name("projectile_server.py")


def main():
    proc = subprocess.Popen([sys.executable, str(SERVER)], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True)
    next_id = 0

    def ask(method, params=None):
        nonlocal next_id
        next_id += 1
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": next_id, "method": method,
                                     "params": params or {}}) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())

    def call(arguments):
        reply = ask("tools/call", {"name": "simulate_projectile", "arguments": arguments})
        result = reply["result"]
        text = result["content"][0]["text"]
        return result["isError"], (text if result["isError"] else json.loads(text))

    checks = []

    def check(name, ok):
        checks.append(ok)
        print(("ok    " if ok else "FALHA ") + name)

    # 1. Protocolo
    check("server/discover -> 'method not found' (o cliente cai no initialize)",
          ask("server/discover").get("error", {}).get("code") == -32601)
    init = ask("initialize", {"protocolVersion": "2025-06-18"})
    check("initialize responde a versão pedida", init["result"]["protocolVersion"] == "2025-06-18")
    tools = ask("tools/list")["result"]["tools"]
    check("tools/list tem simulate_projectile", [t["name"] for t in tools] == ["simulate_projectile"])

    # 2. Física: bola de futebol (0,43 kg, 22 cm) a 30 m/s e 45 graus
    ball = {"speed_m_s": 30, "angle_deg": 45, "mass_kg": 0.43, "diameter_m": 0.22}
    is_error, r = call(ball)
    check("a simulação roda sem erro", not is_error)
    check("alcance sem arrasto = v^2 sin(2θ) / g",
          math.isclose(r["without_drag_exact"]["range_m"], 30 ** 2 / 9.81, rel_tol=1e-4))
    check("integrador sem arrasto bate com a parábola (erro relativo < 1e-6)",
          r["integrator_check"]["relative_error"] < 1e-6)
    check("o arrasto reduz o alcance, a altura e a velocidade de impacto",
          r["with_drag"]["range_m"] < r["without_drag_exact"]["range_m"]
          and r["with_drag"]["max_height_m"] < r["without_drag_exact"]["max_height_m"]
          and r["with_drag"]["impact_speed_m_s"] < 30)
    print(f"      alcance com arrasto {r['with_drag']['range_m']} m, sem arrasto "
          f"{r['without_drag_exact']['range_m']} m: {r['range_reduction_percent']} % menor")

    _, no_air = call({**ball, "air_density_kg_m3": 0})
    check("sem ar, a redução é ~0", abs(no_air["range_reduction_percent"]) < 1e-3)

    check("a simulação converge (repetir com dt/2 muda o alcance < 1e-6)",
          r["convergence_check"]["relative_change"] < 1e-6)

    # Arrasto muito forte (objeto leve e grande): com passo fixo o RK4 ficaria
    # instável e daria alcance zero; o passo tem que ser reduzido sozinho.
    is_error, strong = call({"speed_m_s": 100, "angle_deg": 45, "mass_kg": 1e-4, "diameter_m": 1})
    check("arrasto forte: passo reduzido, alcance > 0 e convergido",
          not is_error and strong["dt_used_s"]["min"] < 1e-3 and strong["with_drag"]["range_m"] > 0
          and strong["convergence_check"]["relative_change"] < 1e-3)

    # 3. Erros voltam para o modelo como resultado, não derrubam o servidor
    is_error, text = call({**ball, "angle_deg": 95})
    check("ângulo inválido devolve isError com a mensagem", is_error and "angle_deg" in text)
    is_error, text = call({**ball, "mass_kg": float("nan")})
    check("NaN é recusado com mensagem clara", is_error and "finite" in text)
    is_error, _ = call({**ball, "angle_deg": 5e-324})
    check("ângulo minúsculo devolve erro em vez de derrubar o servidor", is_error)
    proc.stdin.write("[1, 2]\n")
    proc.stdin.flush()
    check("pedido que não é objeto JSON devolve erro -32600",
          json.loads(proc.stdout.readline()).get("error", {}).get("code") == -32600)
    check("o servidor continua respondendo depois dos erros", "result" in ask("ping"))

    proc.stdin.close()
    proc.wait(timeout=5)
    print(f"\n{sum(checks)}/{len(checks)} verificações passaram")
    sys.exit(0 if all(checks) else 1)


if __name__ == "__main__":
    main()
