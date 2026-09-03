# Ex2 — Do “funciona na minha máquina” ao ambiente reproduzível

Laboratório da disciplina **Cultura e Práticas de DataOps e MLOps**.

Este repositório é a evolução natural de [ex1DataOps](https://github.com/faberhenrique/ex1DataOps). O Ex1 construiu uma esteira simples de CI/CD para um pipeline de vendas. O Ex2 parte do mesmo domínio e pergunta o que ainda falta quando o CI está verde, mas o sistema não é reproduzível.

Mensagem central:

> Código funcionando não significa sistema reproduzível.

## Contexto

O projeto anterior já possuía testes e espaço para CI/CD. Isso reduz regressões no **código**, mas ainda deixa o time dependente do ambiente de cada pessoa:

- versões de bibliotecas diferentes;
- caminhos de arquivo da máquina de quem escreveu o script;
- configuração misturada com o código;
- dificuldade de responder *qual artefato* está em execução.

O CI verde prova que **um** ambiente (o runner) executou **uma** versão do código. Ele não prova que outro engenheiro, outro notebook ou outro servidor obterá o mesmo resultado.

## Cenário

Um novo engenheiro recebeu o projeto. O CI está verde, mas ele não consegue executá-lo localmente. Em outro ambiente o comportamento é diferente. A equipe também não consegue identificar com certeza qual combinação de código e dependências está rodando.

A missão não é reescrever o pipeline de dados. A missão é tornar o sistema:

- reproduzível;
- rastreável;
- configurável;
- containerizado;
- reconstruível;
- passível de rollback.

## Progressão pedagógica

```text
Código
  → Testes
    → CI/CD
      → Artefato
        → Container
          → Configuração externa
            → Infraestrutura reproduzível
              → Versionamento
                → Promoção
                  → Rollback
```

## O que o pipeline faz

O domínio continua sendo **vendas**, como no Ex1. A entrada agora traz quantidade e preço unitário:

| order_id | customer_id | product  | quantity | unit_price | region   |
|----------|-------------|----------|----------|------------|----------|
| 1001     | C001        | Notebook | 2        | 3500.00    | Sudeste  |

O pipeline:

1. lê um CSV;
2. valida colunas, nulos e valores inválidos;
3. calcula `total_amount = quantity * unit_price`;
4. grava um CSV de saída;
5. imprime informações básicas da execução.

A transformação é propositalmente simples. A complexidade deste exercício é **operacional**.

## Missão

Transformar este pipeline em um sistema que outro engenheiro consiga reconstruir sem perguntar “qual Python você usa?” ou “qual pasta você montou?”.

Você deve ser capaz de:

1. executar o mesmo artefato em máquinas diferentes;
2. identificar a imagem pelo commit ou por uma tag de versão;
3. destruir o ambiente e recriá-lo a partir de declaração;
4. voltar para uma versão anterior **sem editar o container vivo**.

## Pré-requisitos

- Python 3.11+ (3.12 recomendado)
- Docker Engine ou Docker Desktop
- Docker Compose v2
- Terraform >= 1.5
- Make (opcional, apenas atalhos)

No Windows, use PowerShell ou WSL2. Os exemplos abaixo incluem as duas formas quando o caminho muda.

## Como começar

```bash
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\Activate.ps1
make install                       # ou: pip install -r requirements-dev.txt
cp .env.example .env
```

Preencha `.env` com valores do **seu** ambiente. Não commite esse arquivo.

```bash
make test
```

Em seguida, tente executar o pipeline na sua máquina. Observe o que acontece — e o que isso revela sobre o estado atual do projeto.

## Desafios

### Desafio 1 — Faça funcionar fora da sua máquina

Execute o pipeline em um ambiente que não seja o notebook de quem criou o código.

Perguntas:

- O que quebra primeiro: caminho, dependência, variável ou permissão?
- O que está no repositório e o que ficou só na cabeça de alguém?
- Passar nos testes locais é a mesma coisa que o sistema ser executável em outro lugar?

### Desafio 2 — Containerize

Empacote a aplicação em uma imagem Docker.

Comandos de referência:

```bash
docker build -t ex2-dataops:v1 .
```

macOS / Linux:

```bash
docker run \
  --env-file .env \
  -v "$(pwd)/data:/app/data" \
  ex2-dataops:v1
```

Windows PowerShell:

```powershell
docker run `
  --env-file .env `
  -v "${PWD}/data:/app/data" `
  ex2-dataops:v1
```

Você também pode usar:

```bash
docker compose up --build --abort-on-container-exit
```

O serviço é um job batch: o container executa o pipeline e encerra. A flag `--abort-on-container-exit` devolve o terminal quando o job termina.

Perguntas:

- O que entra na imagem e o que permanece fora (volume, `.env`, código-fonte no notebook)?
- Qual a diferença entre **empacotar** (imagem) e **orquestrar** (Compose)?
- Por que a tag `v1` é mais útil do que `latest` neste laboratório?

### Desafio 3 — Separe código, configuração e segredo

| Tipo          | Responde                                      | Exemplos                         | Pode commitar? |
|---------------|-----------------------------------------------|----------------------------------|----------------|
| Código        | *O quê* o sistema faz e *como* processa       | transformação, validação         | sim            |
| Configuração  | *Onde* e *com quais parâmetros* ele executa   | `INPUT_PATH`, `ENVIRONMENT`      | exemplo, sim   |
| Segredo       | credencial ou identidade                      | `API_KEY`                        | nunca          |

Use `.env.example` como contrato. O arquivo `.env` é local.

Perguntas:

- O que acontece se um caminho de máquina pessoal permanecer no código-fonte?
- Configuração e segredo podem viajar no mesmo mecanismo (`ENV`)? Qual o risco?
- Onde um segredo fictício ainda não deveria estar?

### Desafio 4 — Evolua o CI

O workflow deve materializar a esteira:

```text
Commit → Test → Build → Container Image → Tag → Artifact
```

A imagem precisa poder ser identificada pelo SHA do commit. `latest` não deve ser o mecanismo principal de identidade.

Publicar em Docker Hub ou GHCR é **opcional**. O workflow precisa passar sem credenciais externas.

Perguntas:

- O que o CI prova depois que passa a construir a imagem?
- Qual a diferença entre versionar o repositório Git e versionar o artefato?
- Se o runner usa Ubuntu e o aluno usa macOS, o que a imagem iguala — e o que ela não iguala?

### Desafio 5 — Declare o ambiente

Na pasta `infra/` existe um esboço de Infrastructure as Code com Terraform e o provider Docker.

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
terraform destroy
```

Atalho: `make infra-plan`, `make infra-up` e `make infra-down` exportam `DOCKER_HOST` a partir do contexto atual do Docker CLI.

Requisito local: o daemon Docker precisa estar em execução. O provider usa `DOCKER_HOST` ou o default; se o `apply` não encontrar o daemon, ajuste `docker_host` conforme os comentários em `terraform.tfvars.example` (Docker Desktop no macOS não usa `/var/run/docker.sock`).

Perguntas:

- O que o `plan` torna visível antes da mudança acontecer?
- O que se perde e o que se preserva com `destroy` seguido de `apply`?
- O container é stateless. A saída do pipeline é stateful. Onde cada um deve viver?

### Desafio 6 — Faça um rollback

Prepare uma demonstração com o seguinte enredo:

```text
v1  →  v2 (problema)  →  rollback  →  v1
```

Uma alteração simples o suficiente para representar uma versão defeituosa: o cálculo de `total_amount` deixa de ser uma multiplicação.

O rollback **não** pode depender de:

- editar o container vivo;
- alterar arquivo manualmente “em produção”;
- SSH;
- reconstruir a versão antiga na mão a partir da memória.

A solução correta usa um **artefato já conhecido** (`ex2-dataops:v1` ou `ex2-dataops:<sha-anterior>`).

Documente os comandos que você usou e o critério que prova que voltou a `v1`.

### Desafio 7 — Decida se Kubernetes é necessário

Kubernetes **não** é parte obrigatória deste exercício.

Responda, com justificativa:

> Este workload realmente precisa de Kubernetes?

Considere:

- o job é batch ou contínuo?
- há requisito de alta disponibilidade?
- quantas instâncias?
- escala prevista;
- número de equipes;
- self-healing;
- rollout avançado;
- custo operacional;
- capacidade do time;
- custo cognitivo.

Não há ponto extra por usar Kubernetes. Uma decisão de **não** adotá-lo, bem argumentada, é maturidade.

Preencha `ARCHITECTURE.md`.

## Critérios de aceite

O trabalho é aceito quando todos os itens abaixo forem verdadeiros:

1. `python -m pytest` passa.
2. A imagem Docker constrói e executa o pipeline com configuração externa e volume de dados.
3. `docker compose up` executa o mesmo fluxo de forma declarativa.
4. O CI executa testes **e** constrói a imagem, tagueada de forma rastreável (SHA e/ou versão). `latest` não é a identidade principal.
5. Código, configuração e segredo estão separados. `.env` não entra no Git. Segredo não permanece no código-fonte.
6. O ambiente Docker/Terraform pode ser destruído e recriado a partir de arquivos versionados.
7. Há uma demonstração de rollback por artefato, não por edição manual.
8. `ARCHITECTURE.md` responde às sete perguntas, incluindo a decisão sobre Kubernetes.

## Entregáveis

- código do pipeline e testes;
- `Dockerfile` e `.dockerignore`;
- `docker-compose.yml`;
- `.env.example` (sem segredo);
- `infra/` com Terraform (sem state nem `terraform.tfvars` com segredo);
- `.github/workflows/ci.yml`;
- `ARCHITECTURE.md` preenchido;
- evidências de execução (logs de `docker run` / `compose` / `terraform` / rollback).

Não entregue Kubernetes, banco, fila ou cloud apenas para “completar o stack”.

## Avaliação

Nota total: **10 pontos**.

| Critério | Pontos |
|----------|--------|
| Container executa corretamente | 2,0 |
| CI testa e gera imagem | 2,0 |
| Separação código / configuração / segredo | 1,5 |
| Ambiente reproduzível | 2,0 |
| Versionamento + rollback | 1,5 |
| Justificativa arquitetural | 1,0 |

Usar Kubernetes **não** adiciona pontos. Uma justificativa sólida de que Docker + scheduler + CI/CD + IaC bastam para este workload é uma ótima decisão.

## Atalhos (Makefile)

```bash
make install
make test
make run
make docker-build
make docker-run
make compose-up
make compose-down
make infra-plan
make infra-up
make infra-down
```

O Makefile não substitui o entendimento dos comandos. Se `make docker-run` falhar por ausência de `.env`, isso faz parte do exercício.

## Estrutura

```text
ex2DataOps/
├── src/pipeline.py
├── tests/
├── data/input/sample.csv
├── data/output/
├── infra/
├── .github/workflows/ci.yml
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
├── requirements-dev.txt
├── .env.example
├── Makefile
├── README.md
└── ARCHITECTURE.md
```

Construa a solução a partir deste README, do código e dos desafios. Preencha `ARCHITECTURE.md` como parte da entrega.

## Relação com o Ex1

| Ex1 | Ex2 |
|-----|-----|
| Pipeline de vendas em Python | O mesmo domínio, com `total_amount` |
| Testes com pytest | Testes continuam sendo a rede de proteção |
| CI como esteira de código | CI também produz **imagem** identificável |
| “Funciona no runner” | “Funciona em qualquer máquina com o artefato” |
| Caminhos relativos no script | Configuração precisa sair do código |
| Sem container | Imagem imutável, tag, rollback |

## Princípio

> O objetivo de IaC e containers é reduzir variabilidade operacional.

> Maturidade não é utilizar Kubernetes. É saber quando a complexidade dele se justifica.
