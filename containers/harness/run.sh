#!/bin/bash
# Harness isolado: o agente roda DENTRO de um container; o modelo é servido
# FORA dele, por um servidor com a API do Ollama (compatível com a da OpenAI).
#
#   ./harness/run.sh "<pergunta>"
#   MODEL=gpt-oss:20b ./harness/run.sh "<pergunta>"
#   OLLAMA_URL=http://outra-maquina:11434 ./harness/run.sh "<pergunta>"
#
# O servidor pode ser o Ollama instalado no seu computador (no WSL com
# networkingMode=mirrored, o Ollama do Windows aparece em localhost), o
# container do ollama isolado (ollama/serve.sh) ou outra máquina.
# O modelo precisa existir nesse servidor. Outras variáveis: veja common.sh.
# OLLAMA_URL é o endereço do servidor, sem o "/v1" (ele é acrescentado aqui;
# se vier, é removido).
set -euo pipefail
source "$(dirname "$0")/../common.sh"
OLLAMA_URL="${OLLAMA_URL:-http://127.0.0.1:$OLLAMA_PORT}"
OLLAMA_URL="${OLLAMA_URL%/}"
OLLAMA_URL="${OLLAMA_URL%/v1}"
STATE="$STATE_DIR/harness"
require_image harness

# Antes de iniciar o agente, confere se há um servidor no endereço.
# Separa host e porta de URLs como http://host:porta/... ou http://[::1]:porta
hostport="${OLLAMA_URL#*://}"
hostport="${hostport%%/*}"
case "$hostport" in
    \[*\]:*) host="${hostport%%]*}"; host="${host#[}"; port="${hostport##*]:}" ;;
    \[*\])   host="${hostport#[}"; host="${host%]}"; port="" ;;
    *:*)     host="${hostport%:*}"; port="${hostport##*:}" ;;
    *)       host="$hostport"; port="" ;;
esac
if [ -z "$port" ]; then
    port=80
    [ "${OLLAMA_URL%%://*}" = https ] && port=443
fi
if ! listening "$host" "$port"; then
    echo "Nenhum servidor de modelos em $OLLAMA_URL." >&2
    echo "Inicie um (o Ollama do seu computador, ou ollama/serve.sh) ou defina OLLAMA_URL." >&2
    exit 1
fi

mkdir -p "$STATE"
render_agent_patch "$STATE/agent.patch.yml" "$OLLAMA_URL/v1"
dsh_container_args "$STATE"

apptainer run "${DSH_ARGS[@]}" \
    "$IMAGES_DIR/harness.sif" \
    --profile headless --patch /home/dsh/agent.patch.yml "$@"
