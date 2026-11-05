# llm-devito

Agentes de IA baseados em LLMs para gerar e analisar modelos de fenômenos físicos descritos
por equações diferenciais, com simulação numérica em [Devito](https://www.devitoproject.org/)

## A ideia

Muitos fenômenos físicos já têm equações conhecidas, mas pouca documentação prática de como
simulá-los e visualizá-los. A proposta é desenvolver um **pipeline** em que um agente parte de uma descrição do problema e chega a uma simulação validada:

```
descrição do fenômeno  ──►  modelo físico  ──►  simulação numérica  ──►  análise  ──►  validação
   + bibliografia           (equações)          (Devito)                               │
                                 ▲                                                     │
                                 └──────────── ajusta até convergir ◄──────────────────┘
                                               (compara com soluções exatas/analíticas)
```

O agente vai chamar ferramentas numéricas, ler os resultados e conferir a
própria resposta contra casos com solução conhecida.

## Componentes

| Peça                                                                | O que faz                                                                             | Por quê                                              |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | O *harness* do agente: conversa com o modelo, chama as ferramentas, guarda as sessões | Para incluir ferramentas como servidores MCP         |
| [Ollama](https://ollama.com/)                                       | Servidor de modelos                                                                   | Permitir o uso de diferentes modelos com troca fácil |
| [Apptainer](https://apptainer.org/)                                 | Containers                                                                            | Garantir a padronização do projeto                   |


## Status

| Etapa                              | Situação                          |
| ---------------------------------- | --------------------------------- |
| Imagens de container               | Construídas e Validadas           |
| Teste de Agente com uma ferramenta | Chegou no resultado esperado      |
| Execução no cluster com GPU        | ⏳ modelado, mas ainda não testado |
| Ferramentas com Devito (EDPs)      | ⏳ ainda não implementado          |
| Pipeline completo                  | ⏳ ainda não implementado          |

## As três variações de container

São **alternativas independentes**, não etapas: cada uma é construída e roda sozinha.

| Variante         | Conteúdo da imagem                    | Quando usar                                                          |
| ---------------- | ------------------------------------- | -------------------------------------------------------------------- |
| `harness-ollama` | harness + servidor de modelos, juntos | **O uso normal.** Um arquivo, um comando; é a forma usada no cluster |
| `harness`        | só o harness                          | Quando o modelo já é servido em outra máquina                        |
| `ollama`         | só o servidor de modelos              | Para baixar modelos ou servir um modelo para vários clientes         |

Em todas, os arquivos dos modelos ficam **fora** da imagem, numa pasta do host.

## Início rápido

Num Linux x86-64 (ou WSL2) com Apptainer instalado:

```bash
git clone https://github.com/pagodee/llm-devito.git
cd llm-devito/containers
./build.sh harness-ollama          # ~3,4 GB; só na primeira vez
./harness-ollama/run.sh "Uma bola de futebol (0,43 kg, 22 cm de diâmetro) é chutada a 30 m/s com ângulo de 45 graus. Quanto o alcance diminui por causa da resistência do ar?"
```

Na primeira execução o modelo padrão (`qwen3:4b`, ~2,5 GB) é baixado para `~/ollama-models`.
O agente chama a ferramenta `simulate_projectile`, que realiza a simulação do lançamento do projétil considerando a resistência do ar e considerando o vácuo, e responde que o alcance cai de ~91,7 m no vácuo para ~36,8 m com arrasto, cerca de 60 % a menos. 

Instalação do Apptainer, as outras variantes, configuração e uso no cluster:
**[docs/setup.md](docs/setup.md)**.

## Estrutura do repositório

| Caminho                                     | Conteúdo                                                                        |
| ------------------------------------------- | ------------------------------------------------------------------------------- |
| `containers/versions.env`                   | Versões de Node, dsh e Ollama usadas nas imagens                                |
| `containers/build.sh`                       | Constrói as imagens a partir das recipes                                        |
| `containers/common.sh`                      | Configuração compartilhada dos scripts de execução (modelo, porta, pastas, GPU) |
| `containers/harness-ollama/`                | Recipe, script de execução e modelo de job SLURM da variante completa           |
| `containers/harness/`, `containers/ollama/` | Recipes e scripts das variantes separadas                                       |
| `agent/`                                    | O agente de teste: configuração do dsh e a ferramenta para teste inicial        |
| `scripts/install-apptainer.sh`              | Instala o Apptainer em Ubuntu/Debian                                            |
| `docs/setup.md`                             | Guia de instalação e uso                                                        |

## Licença

[Apache 2.0](LICENSE).
