#!/bin/bash
# Ollama isolado, terminal A: roda o servidor de modelos num container. Fica em
# primeiro plano mostrando o log, para você ver as requisições chegando.
# Ctrl+C para o servidor.
#
#   ./ollama/serve.sh
#   MODELS_DIR=/outra/pasta OLLAMA_PORT=11500 ./ollama/serve.sh
#
# Os modelos ficam em MODELS_DIR no host, montada em /models no container.
# Apagar o container ou a imagem não mexe neles. Usa GPU NVIDIA se houver
# (veja GPU em common.sh); senão, a CPU.
#
# Também serve para BAIXAR modelos antes de usá-los: num cluster os nós de
# computação costumam não ter internet, então você sobe este servidor no nó
# de login, baixa com client.sh pull e para.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
STATE="$STATE_DIR/ollama"
require_image ollama

# Só um programa pode escutar numa porta
if listening 127.0.0.1 "$OLLAMA_PORT"; then
    echo "A porta $OLLAMA_PORT já está em uso (outro Ollama?). Pare-o ou use OLLAMA_PORT=<outra porta>." >&2
    exit 1
fi

mkdir -p "$MODELS_DIR" "$STATE"
echo "Modelos:  $MODELS_DIR (host)  =  /models (container)"
echo "Servidor: 127.0.0.1:$OLLAMA_PORT   GPU: ${GPU_ARGS[*]:-nenhuma (CPU)}"
echo

apptainer run \
    --containall \
    "${GPU_ARGS[@]}" \
    --home "$STATE:/home/ollama" \
    --bind "$MODELS_DIR:/models" \
    --env OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT" \
    --env OLLAMA_CONTEXT_LENGTH="$CONTEXT_LENGTH" \
    "$IMAGES_DIR/ollama.sif"
