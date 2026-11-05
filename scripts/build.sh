#!/bin/bash
# Constrói a imagem llm-devito.sif (~3,5 GB) a partir de llm-devito.def.
# Sem sudo: o Apptainer usa o modo fakeroot.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
apptainer build --fakeroot --force "$REPO/llm-devito.sif" "$REPO/llm-devito.def"
