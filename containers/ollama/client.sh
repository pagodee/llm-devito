#!/bin/bash
# Ollama isolado, terminal B: conversa com o servidor do terminal A. Cada
# chamada inicia um SEGUNDO container, de vida curta, da mesma imagem, que
# roda o cliente de linha de comando "ollama", fala com o servidor por
# localhost e termina.
#
#   ./ollama/client.sh pull qwen3:4b     baixa um modelo para MODELS_DIR
#   ./ollama/client.sh list              modelos na pasta
#   ./ollama/client.sh run qwen3:4b "Explain what a projectile is in one sentence."
#   ./ollama/client.sh ps                modelos carregados na memória agora
#
# Use o mesmo OLLAMA_PORT do serve.sh, se tiver mudado.
set -euo pipefail
source "$(dirname "$0")/../common.sh"
require_image ollama

apptainer exec \
    --containall \
    --env OLLAMA_HOST="127.0.0.1:$OLLAMA_PORT" \
    "$IMAGES_DIR/ollama.sif" \
    ollama "$@"
