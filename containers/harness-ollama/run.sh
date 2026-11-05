#!/bin/bash
# Harness + ollama: UM container com DOIS processos, ollama serve e o dsh.
# Os modelos ficam fora da imagem, em MODELS_DIR (a mesma pasta do ollama
# isolado). Se o modelo não estiver lá, é baixado na primeira execução.
#
#   ./harness-ollama/run.sh "<pergunta>"
#   MODEL=gpt-oss:20b ./harness-ollama/run.sh "<pergunta>"
#
# Enquanto roda, o log do servidor fica em state/harness-ollama/ollama.log:
#   tail -f state/harness-ollama/ollama.log     (em outro terminal)
# Usa GPU NVIDIA se houver (veja GPU em common.sh); senão, a CPU.
# As flags do apptainer estão explicadas em common.sh.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
STATE="$STATE_DIR/harness-ollama"
require_image harness-ollama

if listening 127.0.0.1 "$OLLAMA_PORT"; then
    echo "A porta $OLLAMA_PORT já está em uso (outro Ollama?). Pare-o ou use OLLAMA_PORT=<outra porta>." >&2
    exit 1
fi

mkdir -p "$MODELS_DIR" "$STATE"
render_agent_patch "$STATE/agent.patch.yml" "http://127.0.0.1:$OLLAMA_PORT/v1"
dsh_container_args "$STATE"

apptainer run "${DSH_ARGS[@]}" \
    "${GPU_ARGS[@]}" \
    --bind "$MODELS_DIR:/models" \
    --env MODEL="$MODEL" \
    --env OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT" \
    --env OLLAMA_CONTEXT_LENGTH="$CONTEXT_LENGTH" \
    "$IMAGES_DIR/harness-ollama.sif" \
    --profile headless --patch /home/dsh/agent.patch.yml "$@"
