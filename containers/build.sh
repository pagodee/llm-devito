#!/bin/bash
# Constrói as imagens (.sif) a partir das recipes (.def).
#
#   ./build.sh harness           harness isolado
#   ./build.sh ollama            ollama isolado
#   ./build.sh harness-ollama    os dois na mesma imagem
#   ./build.sh all               as três
#
# As imagens vão para containers/images/ (ou para IMAGES_DIR), que não entra
# no git. As versões (Node, dsh, Ollama) vêm de versions.env.
#
# Onde construir: qualquer Linux x86-64 com Apptainer >= 1.2 (a versão que
# trouxe os argumentos de build), sem sudo. Em clusters é comum não ser
# permitido construir; nesse caso, construa no seu computador e copie o .sif
# (um único arquivo) para o cluster.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="${IMAGES_DIR:-$HERE/images}"

# shellcheck source=versions.env
source "$HERE/versions.env"

# O Apptainer monta a imagem numa pasta temporária (/tmp por padrão). Se /tmp
# fica na memória RAM (tmpfs, como no WSL), pode faltar espaço para a imagem
# do Ollama (vários GB); nesse caso usamos uma pasta no disco.
if [ -z "${APPTAINER_TMPDIR:-}" ] && [ "$(findmnt -n -o FSTYPE /tmp 2>/dev/null)" = tmpfs ]; then
    export APPTAINER_TMPDIR="$HOME/.apptainer/tmp"
fi
if [ -n "${APPTAINER_TMPDIR:-}" ]; then mkdir -p "$APPTAINER_TMPDIR"; fi

# Construir sem ser root usa o "fakeroot": você age como root só dentro do
# build. No WSL o modo padrão do fakeroot falha ("failed to mount binfmt_misc
# filesystem"), e o segundo modo injeta o programa fakeroot do host, novo
# demais para o Debian 12. Então, no WSL, usamos o modo mais simples: um único
# id de usuário mapeado para root, sem programa auxiliar. Efeito colateral: o
# apt não consegue trocar de usuário, por isso as recipes usam
# APT::Sandbox::User=root (inofensivo em qualquer outro ambiente).
# Fora do WSL, o Apptainer escolhe o modo sozinho.
# Para forçar outras flags:  BUILD_FLAGS="--fakeroot" ./build.sh ...
if [ -z "${BUILD_FLAGS+definido}" ]; then
    if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
        BUILD_FLAGS="--ignore-subuid --ignore-fakeroot-command"
    else
        BUILD_FLAGS=""
    fi
fi

# build <nome da imagem> <recipe> <variáveis de versions.env que a recipe usa...>
build() {
    local name="$1" recipe="$2" var
    local args=()
    shift 2
    for var in "$@"; do args+=(--build-arg "$var=${!var}"); done
    mkdir -p "$IMAGES_DIR"
    echo "=== construindo $IMAGES_DIR/$name.sif a partir de $recipe ==="
    # shellcheck disable=SC2086  # BUILD_FLAGS é uma lista de flags: sem aspas de propósito
    apptainer build $BUILD_FLAGS --force "${args[@]}" "$IMAGES_DIR/$name.sif" "$HERE/$recipe"
}

build_harness()        { build harness        harness/harness.def               NODE_IMAGE DSH_VERSION; }
build_ollama()         { build ollama         ollama/ollama.def                 OLLAMA_IMAGE; }
build_harness_ollama() { build harness-ollama harness-ollama/harness-ollama.def NODE_IMAGE DSH_VERSION OLLAMA_IMAGE; }

case "${1:-}" in
    harness)        build_harness ;;
    ollama)         build_ollama ;;
    harness-ollama) build_harness_ollama ;;
    all)            build_harness; build_ollama; build_harness_ollama ;;
    *) echo "uso: $0 harness|ollama|harness-ollama|all" >&2; exit 1 ;;
esac
ls -lh "$IMAGES_DIR"
