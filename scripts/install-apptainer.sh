#!/bin/bash
# Instala o Apptainer em Ubuntu ou Debian (x86-64) a partir do pacote .deb
# oficial do projeto. Precisa de sudo.
#
#   ./scripts/install-apptainer.sh              instala
#   ./scripts/install-apptainer.sh --dry-run    só mostra qual pacote usaria
#   APPTAINER_VERSION=1.5.5 ./scripts/install-apptainer.sh
#
# Em clusters isso não se aplica: o Apptainer (ou o Singularity, nome antigo
# do mesmo projeto) é instalado pelos administradores. Procure com
# "module avail apptainer" ou "apptainer --version".
set -euo pipefail
VERSION="${APPTAINER_VERSION:-1.5.5}"
DRY_RUN=0
[ "${1:-}" = --dry-run ] && DRY_RUN=1

if command -v apptainer > /dev/null 2>&1; then
    echo "O Apptainer já está instalado: $(apptainer --version)"
    [ "$DRY_RUN" = 1 ] || exit 0
fi

if [ "$(dpkg --print-architecture)" != amd64 ]; then
    echo "Este script só cobre x86-64 (amd64); veja apptainer.org/docs para outras arquiteturas." >&2
    exit 1
fi

# O .deb padrão depende da libfuse3-3. Distribuições recentes (Debian 13
# "trixie", Ubuntu 25.04 em diante) só têm a libfuse3-4, e para elas o
# projeto publica um build separado, o "trixie+".
if apt-cache show libfuse3-3 > /dev/null 2>&1; then
    DEB="apptainer_${VERSION}_amd64.deb"
elif apt-cache show libfuse3-4 > /dev/null 2>&1; then
    DEB="apptainer_${VERSION}-trixie+_amd64.deb"
else
    echo "O apt não conhece nem a libfuse3-3 nem a libfuse3-4." >&2
    echo "A lista de pacotes provavelmente nunca foi baixada: rode 'sudo apt update' e tente de novo." >&2
    exit 1
fi
URL="https://github.com/apptainer/apptainer/releases/download/v${VERSION}/${DEB//+/%2B}"
echo "Pacote: $URL"
[ "$DRY_RUN" = 1 ] && exit 0

if ! command -v curl > /dev/null 2>&1; then
    echo "Este script usa o curl para baixar o pacote: sudo apt install -y curl" >&2
    exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fL -o "$TMP/apptainer.deb" "$URL"
# O apt baixa e lê pacotes como um usuário sem privilégios; ele precisa
# conseguir ler a pasta temporária.
chmod 755 "$TMP"
chmod 644 "$TMP/apptainer.deb"
sudo apt-get install -y "$TMP/apptainer.deb"
apptainer --version
