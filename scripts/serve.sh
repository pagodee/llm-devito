#!/bin/bash
# Sobe o Ollama servindo o modelo MODEL e a interface web do agente, os dois a
# partir da mesma imagem. Não é chamado diretamente: use um serve-<modelo>.sh,
# que define MODEL e CONTEXT_LENGTH e chama este script.
#
# Depois de subir, abra no navegador o link http://127.0.0.1:3080/?token=... que
# aparece no terminal. Ctrl+C desliga tudo.
#
# Pastas no host (fora da imagem):
#   ~/ollama-models   os modelos baixados (MODELS_DIR para trocar)
#   state/            sessões do agente e o log do Ollama (state/ollama.log)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="${MODELS_DIR:-$HOME/ollama-models}"
mkdir -p "$MODELS_DIR" "$REPO/state"

# GPU NVIDIA, se houver (no cluster). Sem ela o Ollama usa a CPU.
GPU=""
if command -v nvidia-smi > /dev/null 2>&1; then GPU="--nv"; fi

# O comando que roda algo dentro da imagem, igual para todos os passos:
# --containall      isola o container: a sua home e as variáveis do host não entram
# --home            a pasta state/ é a home do container (as sessões ficam salvas)
# --bind ...:/models  os modelos, fora da imagem
# --bind ...:/agent:ro  a configuração e a ferramenta do agente, somente leitura
# --env             configurações do Ollama e do dsh. OLLAMA_HOST=127.0.0.1 deixa
#                   o Ollama acessível só nesta máquina (a imagem base usa 0.0.0.0).
#                   GPT_API_KEY é exigida pelo dsh; o Ollama ignora o valor.
RUN=(apptainer exec --containall $GPU
    --home "$REPO/state:/home/dsh"
    --bind "$MODELS_DIR:/models"
    --bind "$REPO/agent:/agent:ro"
    --env OLLAMA_HOST=127.0.0.1:11434
    --env OLLAMA_MODELS=/models
    --env OLLAMA_CONTEXT_LENGTH="$CONTEXT_LENGTH"
    --env MODEL="$MODEL"
    --env CONTEXT_LENGTH="$CONTEXT_LENGTH"
    --env GPT_API_KEY=ollama
    "$REPO/llm-devito.sif")

# 1. O servidor de modelos, em segundo plano. Desligado quando o script termina.
"${RUN[@]}" ollama serve > "$REPO/state/ollama.log" 2>&1 &
OLLAMA_PID=$!
trap 'kill $OLLAMA_PID 2> /dev/null' EXIT

# 2. Espera o Ollama responder
until "${RUN[@]}" ollama list > /dev/null 2>&1; do
    kill -0 $OLLAMA_PID 2> /dev/null || { echo "O Ollama não subiu: veja state/ollama.log" >&2; exit 1; }
    sleep 1
done

# 3. Baixa o modelo, se ele ainda não estiver em MODELS_DIR
"${RUN[@]}" ollama show "$MODEL" > /dev/null 2>&1 || "${RUN[@]}" ollama pull "$MODEL"

# 4. A interface web do agente, em primeiro plano, até o Ctrl+C
"${RUN[@]}" dsh web --patch /agent/agent.patch.yml --no-open
