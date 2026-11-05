#!/bin/bash
# MODELO de job SLURM para rodar o harness-ollama num nó com GPU de um cluster.
# AINDA NÃO TESTADO: nomes de partição e de GPU, limites e caminhos variam de
# cluster para cluster. Confira a documentação do seu antes de usar.
#
# Preparação (uma vez, no nó de login, que tem internet):
#   1. Clone o repositório e copie harness-ollama.sif para containers/images/
#      (construído no seu computador, se o cluster não permitir builds).
#   2. Baixe o modelo para a pasta compartilhada, porque os nós de computação
#      costumam não ter internet (precisa também do ollama.sif). Use a mesma
#      pasta que o job usa (abaixo: $SCRATCH, ou $HOME se não houver $SCRATCH):
#        export MODELS_DIR=${SCRATCH:-$HOME}/ollama-models
#        containers/ollama/serve.sh                          # terminal 1
#        containers/ollama/client.sh pull gpt-oss:20b        # terminal 2
#   3. Se o Apptainer for um módulo do cluster: module load apptainer
#
# Enviar o job, a partir da raiz do repositório:
#   sbatch containers/harness-ollama/slurm-job.sh "<pergunta>"
# A saída vai para llm-devito-<número do job>.log.
#
#SBATCH --job-name=llm-devito
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=llm-devito-%j.log
set -euo pipefail

# O SLURM executa uma CÓPIA deste script em outra pasta, então o caminho do
# repositório vem da pasta de onde o sbatch foi chamado (ou de REPO_DIR, se
# você definir: sbatch --export=ALL,REPO_DIR=/caminho/llm-devito ...).
REPO_DIR="${REPO_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}}"
RUN="$REPO_DIR/containers/harness-ollama/run.sh"
if [ ! -x "$RUN" ]; then
    echo "Não encontrei $RUN. Envie o job a partir da raiz do repositório ou defina REPO_DIR." >&2
    exit 1
fi
JOB="${SLURM_JOB_ID:-manual}"

export MODEL="${MODEL:-gpt-oss:20b}"
export MODELS_DIR="${MODELS_DIR:-${SCRATCH:-$HOME}/ollama-models}"
# Uma pasta de estado por job, para jobs simultâneos não se misturarem
export STATE_DIR="${STATE_DIR:-${SCRATCH:-$HOME}/llm-devito-state/$JOB}"
# Num nó compartilhado com outros jobs a porta 11434 pode estar ocupada: cada
# job usa uma porta derivada do próprio número. Atenção: "localhost" num nó
# compartilhado é visível para os outros usuários do mesmo nó.
export OLLAMA_PORT="${OLLAMA_PORT:-$((20000 + ${SLURM_JOB_ID:-0} % 10000))}"
export GPU="${GPU:-nvidia}"

exec "$RUN" "$@"
