# Instalação e uso

Este guia cobre um computador Linux (ou Windows com WSL2) e, no fim, o uso num cluster.
Tudo o que o agente precisa vem dentro das imagens: no
computador basta o **Apptainer**.

Testado em: WSL2 com Ubuntu 26.04 e Apptainer 1.5.5.

- [1. Requisitos](#1-requisitos)
- [2. Instalar o Apptainer](#2-instalar-o-apptainer)
- [3. Construir as imagens](#3-construir-as-imagens)
- [4. Testar a ferramenta (sem modelo)](#4-testar-a-ferramenta-sem-modelo)
- [5. Rodar as variantes](#5-rodar-as-variantes)
- [6. Configuração](#6-configuração)
- [7. Onde ficam os dados](#7-onde-ficam-os-dados)
- [8. No cluster](#8-no-cluster)
- [9. Problemas comuns](#9-problemas-comuns)

## 1. Requisitos

|           |                                                                                                    |
| --------- | -------------------------------------------------------------------------------------------------- |
| Sistema   | Linux x86-64 (amd64), ou Windows 10/11 com WSL2                                                    |
| Apptainer | 1.2 ou mais novo                                                                                   |
| Disco     | ~7 GB para as três imagens + o tamanho dos modelos (`qwen3:4b`: 2,5 GB)                            |
| Memória   | o modelo `qwen3:4b` instalado  usa ~5 GB de RAM na CPU                                             |
| GPU       | Opcional. GPU NVIDIA com driver instalado é usada automaticamente, sem a presença dela roda na CPU |

### Só no Windows: WSL2

Num PowerShell como administrador, depois reinicie:

```powershell
wsl --install
```

O Ubuntu recém-instalado não tem a lista de pacotes: rode `sudo apt update` antes de qualquer
`apt install`.

## 2. Instalar o Apptainer

Em Ubuntu ou Debian:

```bash
./scripts/install-apptainer.sh --dry-run    # mostra qual pacote vai usar
./scripts/install-apptainer.sh
apptainer --version
```

O script escolhe o pacote certo: distribuições recentes (Ubuntu 25.04+, Debian 13) precisam
do build `trixie+` do Apptainer, porque só têm a `libfuse3-4`.

Em outras distribuições, veja a [documentação do Apptainer](https://apptainer.org/docs/admin/main/installation.html).
Em clusters, o Apptainer é instalado pelos administradores (`module avail apptainer`); às
vezes aparece com o nome antigo, `singularity`.

## 3. Construir as imagens

```bash
cd containers
./build.sh harness-ollama     # a variante completa (~3,4 GB)
./build.sh harness            # só o harness (~230 MB)
./build.sh ollama             # só o servidor de modelos (~3,2 GB)
./build.sh all                # as três
```

As imagens vão para `containers/images/`. O build não precisa de sudo. Na primeira vez ele
baixa as imagens base do Docker Hub (alguns minutos); depois elas ficam em cache
(`~/.apptainer/cache`).

- **Versões:** ficam em `containers/versions.env`. Para atualizar o dsh ou o Ollama, mude ali
  e reconstrua; as três recipes leem do mesmo arquivo.
- **WSL:** o `build.sh` detecta o WSL sozinho e usa flags de *fakeroot* que funcionam nele.
  Para usar outras flags: `BUILD_FLAGS="--fakeroot" ./build.sh ...`.
- **Para conferir uma imagem:** `apptainer inspect --labels images/harness-ollama.sif` mostra
  as versões, e `apptainer inspect --deffile ...` mostra a recipe guardada dentro dela.

## 4. Testar a ferramenta (sem modelo)

A ferramenta do agente é um servidor MCP em Python puro (`agent/projectile_server.py`). Este
teste conversa com ela pelo protocolo, como o dsh faria, e confere a física, em segundos:

```bash
python3 agent/test_projectile_server.py
# ou com o Python da imagem:
apptainer exec --containall --bind agent:/agent:ro containers/images/harness.sif \
    python3 /agent/test_projectile_server.py
```

Esperado: `15/15 verificações passaram`. Além da física , o teste confere que entradas
inválidas voltam como erro para o modelo sem derrubar o servidor.

## 5. Rodar as variantes

Os comandos abaixo são executados dentro de `containers/`. Só um servidor pode usar uma
porta por vez: antes de cada variante, pare o servidor da anterior (ou use outra porta,
veja a [seção 6](#6-configuração)).

A pergunta de teste usada abaixo:

```bash
Q="Uma bola de futebol (0,43 kg, 22 cm de diâmetro) é chutada a 30 m/s com ângulo de 45 graus. Quanto o alcance diminui por causa da resistência do ar?"
```

Resposta esperada: o agente chama `simulate_projectile` e informa alcance de ~36,8 m com
arrasto contra ~91,7 m sem ar (≈ 60 % menor). A ferramenta também devolve duas checagens de
precisão: o integrador sem arrasto contra a parábola exata (erro relativo ~10⁻⁸) e a mesma
simulação com metade do passo (mudança ~10⁻⁷).

O modelo recebe uma única ferramenta, `simulate_projectile`: o shell, os arquivos, a web e as
demais ferramentas internas do dsh estão desligados em `agent/agent.patch.template.yml`.

### harness-ollama

```bash
./harness-ollama/run.sh "$Q"
```

Um container, dois processos: o script inicia `ollama serve` em segundo plano, espera ele
responder, baixa o modelo se ele ainda não estiver na pasta de modelos, mostra a lista de
processos do container e então inicia o dsh. Para acompanhar o servidor, em outro terminal:
`tail -f state/harness-ollama/ollama.log`.

### ollama isolado

Terminal A, o servidor:

```bash
./ollama/serve.sh
```

Terminal B, o cliente:

```bash
./ollama/client.sh pull qwen3:4b      # baixa para ~/ollama-models
./ollama/client.sh list
./ollama/client.sh run qwen3:4b "Explain what a projectile is in one sentence."
./ollama/client.sh ps                 # modelo carregado, e se está na CPU ou na GPU
```

### harness isolado

Precisa de um servidor de modelos já rodando, com o modelo disponível. Por exemplo, com o
`ollama/serve.sh` do item anterior aberto:

```bash
./harness/run.sh "$Q"
OLLAMA_URL=http://outra-maquina:11434 ./harness/run.sh "$Q"     # servidor em outro lugar
```

## 6. Configuração

Todos os scripts de execução leem os mesmos padrões, de `containers/common.sh`. Qualquer um
pode ser trocado na hora:

```bash
MODEL=gpt-oss:20b OLLAMA_PORT=11500 ./harness-ollama/run.sh "$Q"
```

| Variável | Padrão | O que é |
|---|---|---|
| `MODEL` | `qwen3:4b` | Modelo usado pelo agente (qualquer um da [biblioteca do Ollama](https://ollama.com/library) com suporte a ferramentas) |
| `OLLAMA_PORT` | `11434` | Porta do servidor de modelos |
| `OLLAMA_URL` | `http://127.0.0.1:$OLLAMA_PORT` | Só no harness isolado: endereço do servidor (sem o `/v1`) |
| `CONTEXT_LENGTH` | `16384` | Contexto, em tokens, usado pelo servidor **e** informado ao dsh |
| `MODELS_DIR` | `~/ollama-models` | Pasta do host com os arquivos dos modelos |
| `STATE_DIR` | `containers/state` | Pasta do host com as homes dos containers |
| `IMAGES_DIR` | `containers/images` | Onde estão os `.sif` |
| `GPU` | `auto` | `auto` usa GPU NVIDIA se houver; `nvidia` força; `none` desliga |

A forma `VARIÁVEL=valor ./script.sh` é do shell do Linux (bash): define a variável só para
aquele comando. Para valer na sessão inteira do terminal, use `export VARIÁVEL=valor`; para
valer sempre, coloque o `export` no fim do `~/.bashrc`.

O agente em si (modelo, instruções, ferramentas habilitadas) é configurado em
`agent/agent.patch.template.yml`, um *patch* aplicado sobre o perfil `headless` do dsh.

### Usar outro modelo

Qualquer modelo da biblioteca do Ollama que suporte chamada de ferramentas serve. A lista
filtrada está em [ollama.com/search?c=tools](https://ollama.com/search?c=tools). Os nomes
têm a forma `família:tamanho`, como `qwen3:8b` ou `gpt-oss:20b`.

**1. Confira se o modelo cabe.** A memória necessária é aproximadamente o tamanho do
arquivo do modelo  mais 1 a 2 GB para o contexto. Na CPU, essa
memória é a RAM; na GPU, é a memória da placa. Se não couber inteiro na GPU, o Ollama divide
o modelo entre GPU e CPU, e fica bem mais lento.

| Modelo | Arquivo | Observação |
|---|---|---|
| `qwen3:4b` | 2,5 GB | O padrão: roda em qualquer máquina, mas erra mais |
| `qwen3:8b` | 5,2 GB | Um meio-termo para CPU com 16 GB de RAM |
| `gpt-oss:20b` | 14 GB | Bem melhor em seguir instruções; pede GPU ou bastante RAM |

**2. Baixe o modelo.** O harness-ollama baixa sozinho na primeira execução, então este passo
é opcional:

```bash
./ollama/serve.sh                     # terminal A
./ollama/client.sh pull qwen3:8b      # terminal B
```

**3. Rode com ele:**

```bash
MODEL=qwen3:8b ./harness-ollama/run.sh "$Q"
```

O script gera a configuração do agente com esse modelo a cada execução; não há arquivo
para editar.


**4. Gerenciar os modelos baixados,** com o `ollama/serve.sh` rodando:

```bash
./ollama/client.sh list               # o que está em ~/ollama-models, com tamanhos
./ollama/client.sh rm qwen3:4b        # apaga um modelo da pasta
```

No cluster, o modelo do job é escolhido do mesmo jeito, passando a variável pelo `sbatch`:
`sbatch --export=ALL,MODEL=qwen3:8b containers/harness-ollama/slurm-job.sh "<pergunta>"`.

## 7. Onde ficam os dados

As imagens são somente leitura. Tudo o que precisa persistir é uma pasta do host montada no
container:

| No host                 | No container                           | Conteúdo                                                           |
| ----------------------- | -------------------------------------- | ------------------------------------------------------------------ |
| `MODELS_DIR`            | `/models`                              | Arquivos dos modelos (GBs). Apagar uma imagem não apaga os modelos |
| `agent/`                | `/agent`                               | A ferramenta. O agente a usa, mas não pode alterá-la               |
| `STATE_DIR/<variante>/` | a home (`/home/dsh` ou `/home/ollama`) | Sessões do dsh, log do Ollama, configuração gerada                 |

Os scripts usam `--containall`: o container não vê a sua `$HOME`, as suas variáveis de
ambiente nem os seus processos. Por padrão o Apptainer montaria a `$HOME` inteira, e o
agente veria todos os seus arquivos; o [SAFETY.md do dsh](https://github.com/deepseek-ai/deepseek-harness)
recomenda isolamento.

A rede **não** é isolada: `localhost` dentro do container é o `localhost` do host. Por isso o
Ollama escuta só em `127.0.0.1`, e não na rede.

`containers/state/` contém conversas e uma chave privada que o Ollama gera
(`.ollama/id_ed25519`) que está no `.gitignore`.

## 8. No cluster

>  Ainda não testado. Nomes de partição e de GPU, limites e caminhos variam entre clusters.

Um cluster, resumido: você entra por `ssh` no **nó de login** , e os programas rodam nos **nós de computação**, quando o **escalonador** encontrar os recursos que o job pediu. As pastas home/scratch são compartilhadas entre os nós.

1. **Imagem.** Muitos clusters não permitem construir imagens. Construa no seu computador e
   copie o arquivo:
   ```bash
   scp containers/images/harness-ollama.sif usuario@cluster:llm-devito/containers/images/
   ```
2. **Modelos.**  Baixe o modelo antes, no nó de
   login, com o ollama isolado (precisa também do `ollama.sif`), na mesma pasta que o job usa
   (`$SCRATCH`, ou `$HOME` se o cluster não tiver `$SCRATCH`):
   ```bash
   export MODELS_DIR=${SCRATCH:-$HOME}/ollama-models
   ./containers/ollama/serve.sh                        # terminal 1
   ./containers/ollama/client.sh pull gpt-oss:20b      # terminal 2 (com o mesmo MODELS_DIR)
   ```
3. **Job.** Ajuste o cabeçalho `#SBATCH` de `containers/harness-ollama/slurm-job.sh` e envie
   a partir da raiz do repositório:
   ```bash
   sbatch containers/harness-ollama/slurm-job.sh "<pergunta>"
   ```
   O job usa `--nv` (GPU NVIDIA), repassa ao container as GPUs que o SLURM reservou
   (`CUDA_VISIBLE_DEVICES`), usa uma porta derivada do número do job (para não colidir com
   outros jobs no mesmo nó) e uma pasta de estado por job. A saída vai para
   `llm-devito-<job>.log`, que contém a conversa inteira e está no `.gitignore`.

   Atenção: num nó compartilhado, `localhost` é visível para os outros usuários do mesmo nó,
   então eles poderiam usar o servidor de modelos do seu job enquanto ele roda.

## 9. Problemas comuns

| Sintoma                                | Causa e solução                                                                                                                           |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `A porta 11434 já está em uso`         | Outro servidor (outro Ollama instalado na máquina, ou outra variante) está na porta. Pare-o ou use `OLLAMA_PORT=<outra>`                  |
| `Nenhum servidor de modelos em ...`    | Não há servidor no endereço. Inicie um ou ajuste `OLLAMA_URL`                                                                             |
| `A imagem ... não existe`              | Construa com `./build.sh <variante>`                                                                                                      |

