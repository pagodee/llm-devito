#!/bin/bash
# Serve o Qwen3 4B (~2,5 GB). Roda em CPU ou em GPU pequena.
export MODEL=qwen3:4b
export CONTEXT_LENGTH=16384
exec "$(dirname "$0")/serve.sh"
