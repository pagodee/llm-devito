#!/bin/bash
# Serve o gpt-oss 20B (~14 GB). Precisa de GPU com ~16 GB ou de bastante RAM.
export MODEL=gpt-oss:20b
export CONTEXT_LENGTH=16384
exec "$(dirname "$0")/serve.sh"
