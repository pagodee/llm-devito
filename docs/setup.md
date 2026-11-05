# Instalação e uso

Ambiente de desenvolvimento: **Ubuntu (nativo), x86-64**. Tudo o que o agente precisa vem
dentro da imagem; no computador basta o Apptainer.

## 1. Requisitos

|           |                                                                         |
| --------- | ----------------------------------------------------------------------- |
| Sistema   | Linux x86-64 (Ubuntu ou Debian para o script de instalação)             |
| Apptainer | 1.2 ou mais novo                                                        |
| Disco     | ~3,5 GB para a imagem + os modelos (`qwen3:4b`: 2,5 GB)                 |
| Memória   | `qwen3:4b` usa ~5 GB de RAM na CPU                                      |
| GPU       | Opcional. GPU NVIDIA com driver é usada automaticamente; sem ela, CPU   |

## 2. Instalar o Apptainer

```bash
sudo apt update
./scripts/install-apptainer.sh
apptainer --version
```

O script baixa o pacote `.deb` oficial e escolhe o build certo para a distribuição (Ubuntu
25.04+ precisa do build `trixie+`). Em clusters o Apptainer já vem instalado
(`module avail apptainer`).

## 3. Construir a imagem

```bash
./scripts/build.sh
```

Gera `llm-devito.sif` na raiz do repositório. Não precisa de sudo. As versões de Ollama,
Node e dsh estão escritas em `llm-devito.def`; para conferir as de uma imagem já construída:
`apptainer inspect --labels llm-devito.sif`.

## 4. Servir um modelo

```bash
./scripts/serve-qwen3-4b.sh
```

O container sobe com dois processos:

1. `ollama serve`, o servidor de modelos, em `127.0.0.1:11434` (log em `state/ollama.log`);
2. `dsh web`, a interface do agente, em **http://127.0.0.1:3080**.

Antes de abrir a interface ele confere se o modelo está em `~/ollama-models` e, se não
estiver, baixa. `Ctrl+C` desliga os dois.

### Adicionar um modelo

Copie um script e troque o nome do modelo:

```bash
cp scripts/serve-qwen3-4b.sh scripts/serve-qwen3-8b.sh
# edite: MODEL=qwen3:8b
```

O modelo precisa suportar chamada de ferramentas ([lista](https://ollama.com/search?c=tools)).
Memória necessária ≈ tamanho do arquivo do modelo + 1 a 2 GB de contexto.

| Modelo        | Arquivo | Observação                                    |
| ------------- | ------- | --------------------------------------------- |
| `qwen3:4b`    | 2,5 GB  | Roda em qualquer máquina, mas erra mais       |
| `qwen3:8b`    | 5,2 GB  | Meio-termo para CPU com 16 GB de RAM          |
| `gpt-oss:20b` | 14 GB   | Segue melhor as instruções; pede GPU ou RAM   |

## 5. O agente

`agent/agent.patch.yml` configura o dsh: aponta para o Ollama do container, usa o modelo do
script e cria o agente **Física**, padrão nas sessões novas, cuja única ferramenta é
`simulate_projectile` (`agent/projectile_server.py`, um servidor MCP em Python puro). Os
agentes normais do dsh continuam disponíveis no seletor da interface.

Testar a ferramenta sem modelo (segundos):

```bash
apptainer exec --containall --bind agent:/agent:ro llm-devito.sif \
    python3 /agent/test_projectile_server.py
```

Esperado: `15/15 verificações passaram`.

## 6. Onde ficam os dados

| No host           | No container | Conteúdo                                       |
| ----------------- | ------------ | ---------------------------------------------- |
| `~/ollama-models` | `/models`    | Os modelos (GBs)                               |
| `agent/`          | `/agent`     | Configuração e ferramenta, somente leitura     |
| `state/`          | `/home/dsh`  | Sessões do agente, log do Ollama               |

O `--containall` isola o container da sua home e das suas variáveis de ambiente (o
[SAFETY.md do dsh](https://github.com/deepseek-ai/deepseek-harness) recomenda isolamento).
A rede não é isolada: `127.0.0.1` dentro do container é o mesmo do host, por isso o
navegador do host acessa a interface.

## 7. Problemas comuns

| Sintoma                                        | Causa                                                                                                   |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| O agente usa um modelo/servidor inesperado     | Já existe um Ollama na porta 11434 (por exemplo, instalado no sistema). Pare-o: `sudo systemctl stop ollama` |
| Interface não abre em 127.0.0.1:3080           | A porta 3080 está ocupada por outro programa, ou o container ainda está baixando o modelo               |
