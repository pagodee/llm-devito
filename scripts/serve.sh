#!/bin/bash
# Sobe o container: Ollama servindo o modelo MODEL + a interface web do agente.
# Não é chamado diretamente: use um serve-<modelo>.sh, que define MODEL e
# CONTEXT_LENGTH e chama este script.
#
# Depois de subir, abra http://127.0.0.1:3080 no navegador. Ctrl+C desliga tudo.
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

# --containall      isola o container: a sua home e as variáveis do host não entram
# --home            a pasta state/ é a home do container (as sessões ficam salvas)
# --bind ...:/models  os modelos, fora da imagem
# --bind ...:/agent:ro  a configuração e a ferramenta do agente, somente leitura
# --env             variáveis lidas pelo Ollama e pelo dsh (GPT_API_KEY é
#                   exigida pelo dsh; o Ollama ignora o valor)
apptainer run --containall $GPU \
    --home "$REPO/state:/home/dsh" \
    --bind "$MODELS_DIR:/models" \
    --bind "$REPO/agent:/agent:ro" \
    --env MODEL="$MODEL" \
    --env CONTEXT_LENGTH="$CONTEXT_LENGTH" \
    --env OLLAMA_CONTEXT_LENGTH="$CONTEXT_LENGTH" \
    --env GPT_API_KEY=ollama \
    "$REPO/llm-devito.sif"
