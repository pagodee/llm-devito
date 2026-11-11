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

| Peça                                                                | O que faz                                                                             |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | O *harness* do agente: conversa com o modelo, chama as ferramentas, interface web     |
| [Ollama](https://ollama.com/)                                       | Servidor de modelos                                                                   |
| [Apptainer](https://apptainer.org/)                                 | Container: uma imagem com tudo, a mesma no computador e no cluster                    |

Uma única imagem (`llm-devito.def`) traz o Ollama e o harness: só o software instalado,
sem lógica. Os scripts em `scripts/` decidem o que rodar: o `serve.sh` usa a imagem para
dois processos, o `ollama serve` e o `dsh web`, a interface do agente no navegador. Os
modelos ficam **fora** da imagem, em `~/ollama-models`.

## Uso

Num Linux x86-64 com Apptainer instalado (ver [docs/setup.md](docs/setup.md)):

```bash
git clone https://github.com/pagodee/llm-devito.git
cd llm-devito
./scripts/build.sh               # constrói llm-devito.sif (~3,5 GB), só na primeira vez
./scripts/serve-qwen3-4b.sh      # sobe o Ollama com o qwen3:4b + a interface web
```

Abra no navegador o link que aparece no terminal (`http://127.0.0.1:3080/?token=...`; sem o
token a interface recusa o acesso). `Ctrl+C` no terminal desliga tudo.

Se o modelo ainda não estiver em `~/ollama-models`, ele é baixado na primeira vez. Para outro
modelo, use outro script (`./scripts/serve-gpt-oss-20b.sh`) ou crie um copiando um dos
existentes.

A sessão nova abre com o agente **Física**, que tem uma única ferramenta,
`simulate_projectile`. Pergunta de teste:

> Uma bola de futebol (0,43 kg, 22 cm de diâmetro) é chutada a 30 m/s com ângulo de 45 graus.
> Quanto o alcance diminui por causa da resistência do ar?

Resposta esperada: ~36,8 m com arrasto contra ~91,7 m no vácuo, cerca de 60 % a menos.

## Estrutura

| Caminho                        | Conteúdo                                                        |
| ------------------------------ | --------------------------------------------------------------- |
| `llm-devito.def`               | A recipe da imagem: só o software, com as versões fixas         |
| `scripts/build.sh`             | Constrói a imagem                                               |
| `scripts/serve-<modelo>.sh`    | Serve um modelo específico (um script por modelo)               |
| `scripts/serve.sh`             | Os passos comuns (Ollama, modelo, interface), chamado pelos scripts de modelo |
| `scripts/install-apptainer.sh` | Instala o Apptainer em Ubuntu/Debian                            |
| `agent/`                       | O agente de teste: configuração do dsh e a ferramenta MCP       |
| `docs/setup.md`                | Instalação e detalhes                                           |

## Status

| Etapa                              | Situação                           |
| ---------------------------------- | ---------------------------------- |
| Imagem (Ollama + harness)          | Construída                         |
| Agente com uma ferramenta, via web | Testado                            |
| Execução no cluster com GPU        | ⏳ ainda não testado                |
| Ferramentas com Devito (EDPs)      | ⏳ ainda não implementado           |
| Pipeline completo                  | ⏳ ainda não implementado           |

## Licença

[Apache 2.0](LICENSE).
