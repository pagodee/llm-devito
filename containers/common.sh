# Configuração compartilhada pelos scripts de execução (run.sh, serve.sh,
# client.sh). Não é executado sozinho: cada script faz "source" deste arquivo.
#
# Tudo aqui é um PADRÃO, e qualquer valor pode ser trocado na hora de rodar:
#   MODEL=gpt-oss:20b OLLAMA_PORT=11500 ./harness-ollama/run.sh "pergunta"
#
#   variável        o que é                                         padrão
#   MODEL           modelo usado pelo agente                        qwen3:4b
#   OLLAMA_PORT     porta do servidor de modelos                    11434
#   CONTEXT_LENGTH  contexto (tokens) do servidor E do dsh          16384
#   MODELS_DIR      pasta do host com os arquivos dos modelos       ~/ollama-models
#   STATE_DIR       pasta do host com as homes dos containers       containers/state
#                   (sessões do dsh, logs); uma subpasta por imagem
#   IMAGES_DIR      onde estão os .sif                              containers/images
#   GPU             auto: usa GPU NVIDIA se houver | nvidia | none  auto

CONTAINERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$CONTAINERS_DIR/.." && pwd)"
AGENT_DIR="$REPO_DIR/agent"

MODEL="${MODEL:-qwen3:4b}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-16384}"
MODELS_DIR="${MODELS_DIR:-$HOME/ollama-models}"
STATE_DIR="${STATE_DIR:-$CONTAINERS_DIR/state}"
IMAGES_DIR="${IMAGES_DIR:-$CONTAINERS_DIR/images}"

for _var in OLLAMA_PORT CONTEXT_LENGTH; do
    case "${!_var}" in
        ''|*[!0-9]*) echo "$_var deve ser um número inteiro (recebido: '${!_var}')" >&2; exit 1 ;;
    esac
done
if [ "$((10#$OLLAMA_PORT))" -lt 1 ] || [ "$((10#$OLLAMA_PORT))" -gt 65535 ]; then
    echo "OLLAMA_PORT deve estar entre 1 e 65535 (recebido: '$OLLAMA_PORT')" >&2
    exit 1
fi

# GPU. A flag --nv torna visível dentro do container o driver NVIDIA do host
# (a imagem do Ollama já traz as bibliotecas CUDA). Em clusters com SLURM, a
# variável CUDA_VISIBLE_DEVICES diz quais GPUs o job recebeu; como
# --containall não repassa variáveis do host, ela é repassada aqui, senão o
# Ollama poderia usar GPUs de outros jobs. Sem GPU, o Ollama usa a CPU.
GPU_ARGS=()
case "${GPU:-auto}" in
    auto)   if command -v nvidia-smi > /dev/null 2>&1; then GPU_ARGS=(--nv); fi ;;
    nvidia) GPU_ARGS=(--nv) ;;
    none)   ;;
    *) echo "GPU deve ser auto, nvidia ou none (recebido: '$GPU')" >&2; exit 1 ;;
esac
if [ ${#GPU_ARGS[@]} -gt 0 ] && [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
    GPU_ARGS+=(--env "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES")
fi

# listening <host> <porta>: verdadeiro se algum programa aceita conexões ali.
# Usa o /dev/tcp do próprio bash, sem precisar de curl ou nc. O "timeout"
# evita esperar minutos por uma máquina remota que não responde.
listening() {
    timeout 5 bash -c 'exec 3<> "/dev/tcp/$1/$2"' _ "$1" "$2" 2> /dev/null
}

# require_image <nome>: para com uma mensagem clara se o .sif não existe
require_image() {
    if [ ! -f "$IMAGES_DIR/$1.sif" ]; then
        echo "A imagem $IMAGES_DIR/$1.sif não existe. Construa com: $CONTAINERS_DIR/build.sh $1" >&2
        exit 1
    fi
}

# render_agent_patch <arquivo de saída> <URL base da API>
# Gera a configuração do agente a partir do modelo em agent/, preenchendo o
# modelo, o endereço do servidor e o contexto.
render_agent_patch() {
    sed -e "s|@MODEL@|$(sed_escape "$MODEL")|g" \
        -e "s|@BASE_URL@|$(sed_escape "$2")|g" \
        -e "s|@CONTEXT_LENGTH@|$CONTEXT_LENGTH|g" \
        "$AGENT_DIR/agent.patch.template.yml" > "$1"
}

# Escapa os caracteres que o sed trataria como especiais na substituição
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Flags comuns aos dois scripts que rodam o dsh (harness e harness-ollama):
#   --containall   isolamento: /tmp novo, lista de processos própria, nenhuma
#                  variável de ambiente do host, e a sua $HOME NÃO é montada
#                  (o padrão do Apptainer montaria ela inteira, o que o
#                  SAFETY.md do dsh desaconselha: o agente veria seus arquivos)
#   --home A:B     a pasta A do host é a home B do container; o dsh grava as
#                  sessões ali, então elas sobrevivem ao fim do container
#   --bind A:B:ro  a pasta A do host aparece em B, somente leitura: o agente
#                  usa as ferramentas de agent/ mas não pode alterá-las
#   --env K=V      passa uma variável para dentro (--containall não passa nenhuma);
#                  GPT_API_KEY é exigida pelo dsh, mas o Ollama ignora o valor
# Não há flag de rede: o Apptainer compartilha a rede do host, então
# "localhost" dentro do container é o mesmo localhost de fora.
dsh_container_args() {  # dsh_container_args <pasta de estado>
    DSH_ARGS=(--containall
              --home "$1:/home/dsh"
              --bind "$AGENT_DIR:/agent:ro"
              --pwd /home/dsh
              --env GPT_API_KEY=ollama)
}
