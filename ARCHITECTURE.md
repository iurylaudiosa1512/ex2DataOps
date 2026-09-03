# Architecture Decision

Preencha este documento como parte da entrega. Seja específico: cite arquivos, tags, comandos e trade-offs reais deste laboratório. Evite respostas genéricas.

## 1. O que está sendo empacotado?

A imagem `ex2-dataops` empacota apenas o necessário para executar o pipeline:
o interpretador Python 3.12 (`python:3.12-slim` como base), as dependências
de runtime (`requirements.txt`, com `pandas==2.2.3` fixado) e o código-fonte
em `src/`. O `Dockerfile` copia `requirements.txt` antes de `src/` para
aproveitar o cache de camadas do Docker: alterar código não invalida a
camada de instalação de dependências. O container roda como usuário não-root
(`appuser`, uid 1000), criado explicitamente no Dockerfile, e o entrypoint
(`CMD ["python", "-m", "src.pipeline"]`) é um processo batch: ele executa o
pipeline uma vez e encerra, não um serviço de longa duração.

## 2. O que ficou fora da imagem e por quê?

Ficaram fora: testes (`tests/`), arquivos de configuração de laboratório
(`docker-compose.yml`, `Makefile`, `ARCHITECTURE.md`, `*.md` exceto o
README), o diretório `infra/` do Terraform, e os dados de entrada/saída
(`data/`). Isso é imposto pelo `.dockerignore`. A razão: dados de entrada e
saída são estado, não artefato de build — devem viver em um volume montado
em tempo de execução (`./data:/app/data` no Compose, ou o par bind
mount/volume nomeado do Terraform), não *dentro* da imagem, senão cada nova
execução exigiria reconstruir a imagem só para trocar o CSV. Testes e infra
não são necessários para *rodar* o pipeline, só para *desenvolvê-lo* ou
*provisioná-lo* — mantê-los fora reduz o tamanho da imagem e a superfície de
coisas que podem vazar (por exemplo, segredos de teste). Configuração
(`INPUT_PATH`, `OUTPUT_PATH`, `ENVIRONMENT`, `API_URL`) e segredo (`API_KEY`)
também ficam fora da imagem: são injetados via variável de ambiente em tempo
de execução (`--env-file .env`, `environment:` do Compose, ou `env = [...]`
no `docker_container` do Terraform), nunca copiados para dentro do
filesystem da imagem.

## 3. Como o ambiente pode ser reconstruído?

Com `infra/` versionado (Terraform) e o `Dockerfile`/`docker-compose.yml`
versionados, qualquer máquina com Docker e Terraform instalados reconstrói o
ambiente inteiro a partir do zero:

```
cd infra
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```

O `main.tf` builda a imagem (`docker_image.pipeline`, a partir do
`Dockerfile` na raiz do repo), cria uma rede Docker dedicada
(`docker_network.lab`), um volume nomeado para a saída
(`docker_volume.output`) e o container (`docker_container.pipeline`) já
configurado com os binds corretos. Nenhum desses recursos depende de estado
manual em uma máquina específica: `terraform destroy` seguido de
`terraform apply` reconstrói tudo de forma idêntica, porque a definição
inteira está em arquivos `.tf` no Git — não em cliques ou comandos avulsos
que alguém rodou uma vez e não documentou.

## 4. Como código, configuração e segredo foram separados?

Seguindo a tabela do Desafio 3: código (`src/pipeline.py`) não contém mais
nenhum valor específico de máquina ou segredo — os defaults no topo do
arquivo (`INPUT_PATH`, `OUTPUT_PATH`, `ENVIRONMENT`, `API_URL`) são apenas
fallbacks neutros para execução local sem `.env`, e `API_KEY` tem default
vazio (nunca um valor fictício "parece real"). A função `_setting()` sempre
prioriza a variável de ambiente sobre o default.

Configuração (`INPUT_PATH`, `OUTPUT_PATH`, `ENVIRONMENT`, `API_URL`) viaja
por `.env` (local, ignorado pelo Git) documentado por `.env.example`
(versionado, sem valores reais) e por `terraform.tfvars` documentado por
`terraform.tfvars.example`. Segredo (`API_KEY`) usa o mesmo mecanismo de
transporte — variável de ambiente —, mas nunca é commitado em lugar nenhum:
`.env` está no `.gitignore`, `terraform.tfvars` também, e a variável
`api_key` no Terraform é declarada `sensitive = true`, o que evita que o
Terraform imprima o valor em logs de `plan`/`apply`. O risco de configuração
e segredo compartilharem o mesmo mecanismo (ENV) é que nada tecnicamente os
distingue no runtime — um `docker inspect` no container ou um `echo $API_KEY`
expõe o segredo da mesma forma que exporia `ENVIRONMENT`. Por isso o
controle real de separação não é o mecanismo de transporte, e sim a
disciplina de nunca commitar o arquivo que popula esse mecanismo (`.env`,
`terraform.tfvars`) e nunca fixar um valor real como default no código.

## 5. Como funciona o rollback?

O rollback é por artefato, não por edição manual. O `ci.yml` builda e
tagueia cada commit exclusivamente pelo SHA curto
(`ex2-dataops:<sha-do-commit>`) — essa é a identidade primária e nunca é
sobrescrita por outro commit. Promover uma versão estável para `v1`, `v2`
etc. é um passo manual e deliberado, feito sobre uma imagem já validada:

```
docker tag ex2-dataops:<sha-validado> ex2-dataops:v1
```

Cenário de demonstração:

1. `v1` — versão correta (`total_amount = quantity * unit_price`), buildada
   e tagueada `ex2-dataops:v1`.
2. `v2` — introduzida uma regressão proposital em `transform_orders`
   (`total_amount` deixa de ser uma multiplicação), buildada como
   `ex2-dataops:v2` e implantada via `terraform apply` com
   `image_tag = "v2"` em `terraform.tfvars`.
3. Constata-se o problema (saída incorreta / teste falhando contra o
   comportamento esperado).
4. Rollback: `terraform.tfvars` volta a `image_tag = "v1"` e
   `terraform apply` é executado de novo. O provider Docker recria o
   container apontando para a imagem `ex2-dataops:v1`, que nunca deixou de
   existir localmente (`keep_locally = true` no `docker_image` do
   Terraform).

Critério que prova o retorno a v1: a saída do pipeline (`data/output/*.csv`)
volta a ter `total_amount` igual a `quantity * unit_price`, e
`docker image inspect ex2-dataops:v1 --format '{{.Id}}'` mostra o mesmo
digest da imagem original — não uma reconstrução manual a partir de memória.
Em nenhum momento o container `v2` é editado por dentro; ele é substituído
por um container novo apontando para a imagem `v1` já existente.

## 6. Kubernetes é necessário?

Não, e a justificativa está nas próprias características da carga de
trabalho:

- **Batch, não contínuo**: o pipeline executa uma vez e encerra
  (`docker_container.pipeline` tem `must_run = false`). Não há requisição
  HTTP contínua a atender, então não há razão para um scheduler que mantenha
  réplicas vivas.
- **Sem requisito de alta disponibilidade**: não existe SLA de "sempre
  disponível" para um job que roda sob demanda ou agendado; uma falha de
  execução é resolvida rodando de novo, não failover instantâneo.
- **Uma única instância**: não há paralelismo horizontal necessário — o CSV
  de entrada deste laboratório não justifica particionamento em múltiplos
  workers.
- **Escala prevista mínima**: o volume de dados é pequeno e não há indicação
  de crescimento que exigiria orquestração elástica.
- **Uma equipe, um serviço**: Kubernetes compensa quando múltiplas equipes
  compartilham um cluster e precisam de isolamento por namespace,
  cotas de recursos, etc. Aqui é um único pipeline mantido por uma pessoa.
- **Self-healing e rollout avançado não são necessários aqui**: o
  "self-healing" que importa neste caso é já resolvido por
  `restart = "no"` + reexecução via CI/Terraform; não há necessidade de
  rolling updates com múltiplas réplicas simultâneas.
- **Custo operacional e cognitivo**: manter um cluster Kubernetes (mesmo
  minikube/kind local) adiciona uma camada inteira de conceitos
  (Deployments, Services, ConfigMaps, Secrets, ingress) para resolver um
  problema que `docker run` + Terraform já resolve com menos peças móveis.

Docker + Compose (para desenvolvimento local) + Terraform (para
provisionamento declarativo) + GitHub Actions (para CI) cobrem os
requisitos reais deste laboratório — reprodutibilidade, rastreabilidade,
configuração externa e rollback — sem introduzir a complexidade de um
orquestrador de containers pensado para cargas contínuas e multi-serviço.

## 7. Quais trade-offs foram assumidos?

- **Tag `v1`/`v2` como promoção manual, não automática**: o CI não marca
  automaticamente todo commit como `v1`. Isso significa que promover uma
  versão exige um passo manual extra (`docker tag`), mas em troca a tag de
  versão nunca é sobrescrita silenciosamente — o que é essencial para o
  rollback funcionar de forma confiável.
- **pandas fixado em `2.2.3` (`==`) em vez de um intervalo (`>=`)**: garante
  reprodutibilidade bit-a-bit entre execuções em máquinas diferentes, ao
  custo de exigir um bump manual deliberado quando uma nova versão for
  necessária, em vez de receber patches automaticamente.
- **Segredo fictício sem valor de fallback no código (`API_KEY = ""`)**: o
  pipeline roda mesmo sem `API_KEY` definida (a função `notify_run` só
  registra se a chave está presente ou ausente, sem fazer chamada de rede),
  o que prioriza reprodutibilidade do laboratório sobre fidelidade a um
  cenário de produção real, onde a ausência do segredo provavelmente deveria
  impedir a execução.
- **Volume de saída como volume Docker nomeado (não bind mount) no
  Terraform**: isola a saída do pipeline do filesystem do host, o que é bom
  para portabilidade, mas torna a inspeção manual do resultado um pouco
  menos direta do que simplesmente abrir uma pasta local (exige
  `docker run --rm -v ex2-dataops-output:/data ... ls /data` ou similar).
- **Sem Kubernetes, sem banco, sem fila**: manter a stack mínima (Docker +
  Compose + Terraform + CI) reduz a curva de aprendizado e o número de
  pontos de falha, ao custo de não demonstrar padrões de orquestração mais
  avançados — trade-off aceitável porque a carga de trabalho real não exige
  esses padrões, e o próprio enunciado do laboratório trata essa escolha
  como maturidade, não como lacuna.

---

## Apêndice — Perguntas de reflexão dos desafios

As sete perguntas numeradas acima são as perguntas formais deste documento.
As perguntas abaixo são as perguntas de reflexão espalhadas pelo README ao
longo dos Desafios 1 a 5. Ficam registradas aqui como comentário, com base
no que foi de fato observado rodando este repositório.

### Desafio 1 — Faça funcionar fora da sua máquina

**O que quebra primeiro: caminho, dependência, variável ou permissão?**
Antes da correção, o que quebraria primeiro era o **caminho**: os defaults
originais de `INPUT_PATH`/`OUTPUT_PATH` em `pipeline.py` apontavam para
`/Users/developer/data/...`, um caminho que só existe na máquina de quem
escreveu o código. Em qualquer outra máquina (inclusive Windows, como neste
caso) esse caminho não existe, e o pipeline falha em `load_orders` com
`FileNotFoundError` antes mesmo de chegar a validar dependências. Depois da
correção, os defaults viraram caminhos relativos (`data/input/sample.csv`),
então esse problema específico não se manifesta mais — mas ele é o exemplo
mais direto de "funciona na minha máquina" que o exercício pede pra
identificar.

**O que está no repositório e o que ficou só na cabeça de alguém?**
Estava no repositório: o código, os testes, o `requirements.txt`. Ficava só
na cabeça de quem escreveu: qual sistema operacional rodava o script, com
qual estrutura de pastas, e qual seria um valor razoável de `API_KEY` para
teste local. O `.env.example` existe justamente para tornar essa
configuração explícita e documentada, em vez de depender de alguém lembrar
ou perguntar.

**Passar nos testes locais é a mesma coisa que o sistema ser executável em
outro lugar?** Não. Os testes usam `tmp_path` (fixture do pytest) para
entrada e saída, então nunca dependem dos defaults hardcoded do módulo — eles
passam mesmo com o bug do caminho pessoal, porque simplesmente não usam esse
caminho. Isso foi observado na prática: os 6 testes passavam tanto antes
quanto depois da correção do path. Testes verdes provam que a *lógica*
funciona; não provam que a *configuração padrão* funciona em outra máquina.
Essa lacuna só aparece ao rodar `python -m src.pipeline` de verdade, que é
exatamente o que expôs o problema.

### Desafio 2 — Containerize

**O que entra na imagem e o que permanece fora?** Ver pergunta 2 do corpo
principal deste documento. Em resumo: código e dependências entram; dados,
configuração e segredo ficam fora, injetados em tempo de execução.

**Qual a diferença entre empacotar (imagem) e orquestrar (Compose)?** A
imagem (`docker build`) é o artefato imutável — o "o quê" será executado.
O Compose (`docker-compose.yml`) é a orquestração de como esse artefato roda
localmente: quais variáveis de ambiente injetar, qual volume montar, qual
política de restart usar. Na prática observada: `docker build -t
ex2-dataops:v1 .` produz a imagem; `docker compose up --build
--abort-on-container-exit` builda essa mesma imagem e já a executa com
`INPUT_PATH`, `OUTPUT_PATH`, `ENVIRONMENT` etc. definidos, sem exigir que a
pessoa monte o comando `docker run` inteiro na mão.

**Por que a tag `v1` é mais útil do que `latest` neste laboratório?**
`latest` não identifica uma versão específica — é só um ponteiro que muda a
cada build, sem registrar o quê mudou. Isso ficou evidente na correção do
CI: antes, `v1` era resultado de builda automática a cada commit, o que
teria o mesmo problema de `latest` (perder a versão anterior). Depois da
correção, `v1` e `v2` são tags atribuídas deliberadamente a builds
específicos e validados, e coexistem no `docker images` (confirmado:
`ex2-dataops:v1` e `ex2-dataops:v2` apareceram lado a lado). Isso é o que
torna o rollback do Desafio 6 possível: `latest` não teria permitido voltar
para uma versão anterior sem antes recriá-la manualmente.

### Desafio 3 — Separe código, configuração e segredo

**O que acontece se um caminho de máquina pessoal permanecer no
código-fonte?** É exatamente o que este repositório tinha antes da correção:
o pipeline funciona na máquina de quem escreveu (porque o caminho existe lá
por acaso) e falha silenciosamente em uso — não por bug de lógica, mas por
uma suposição não documentada sobre o ambiente. É o tipo de falha mais caro
de diagnosticar, porque o código "parece certo".

**Configuração e segredo podem viajar no mesmo mecanismo (ENV)? Qual o
risco?** Podem, e neste projeto viajam — ver a resposta completa na pergunta
4 do corpo principal. O risco central é que o mecanismo de transporte não
impõe controle de acesso diferenciado: uma variável de ambiente de
configuração e uma de segredo são igualmente visíveis para quem tiver acesso
ao processo ou ao `docker inspect`. A separação real vem da disciplina em
volta do mecanismo (o que é versionado, o que é `sensitive`), não do
mecanismo em si.

**Onde um segredo fictício ainda não deveria estar?** No código-fonte
(estava em `API_KEY = "demo-key-123"`, corrigido), em qualquer arquivo
rastreado pelo Git (`.env`, `terraform.tfvars` — ambos no `.gitignore`), em
logs de CI ou de `terraform plan`/`apply` sem proteção (por isso `api_key`
é `sensitive = true` no Terraform), e em mensagens de commit ou comentários
explicativos.

### Desafio 4 — Evolua o CI

**O que o CI prova depois que passa a construir a imagem?** Prova que um
commit específico não só passa nos testes, mas também é *buildável* em um
ambiente limpo (o runner do GitHub Actions, Ubuntu, sem nenhum estado
residual de máquina de desenvolvedor) e produz uma imagem com identidade
rastreável (`ex2-dataops:<sha-curto>`). Não prova que a imagem se comporta
corretamente em produção — isso exigiria testes de integração rodando
*dentro* do container, que este laboratório não pede.

**Qual a diferença entre versionar o repositório Git e versionar o
artefato?** Versionar o Git rastreia *mudanças de código-fonte* — cada
commit é um estado do texto. Versionar o artefato (a imagem Docker) rastreia
*o que de fato pode ser executado*: inclui o resultado do build (camadas,
dependências resolvidas no momento do build) e não só o código. Dois
commits podem gerar imagens diferentes mesmo sem mudar `pipeline.py`, se a
versão de uma dependência não fixada mudar entre builds — motivo pelo qual
fixar `pandas==2.2.3` em vez de deixar sem versão importa: reduz essa
divergência entre "o código não mudou" e "o artefato não mudou".

**Se o runner usa Ubuntu e o aluno usa macOS/Windows, o que a imagem
iguala — e o que ela não iguala?** A imagem iguala o ambiente de *execução*
do pipeline: mesma versão de Python (3.12, fixada pela tag base
`python:3.12-slim`), mesmas dependências (`pandas==2.2.3`), mesmo
filesystem interno, independentemente de o host ser Ubuntu, macOS ou
Windows — confirmado na prática, já que os testes rodaram em ambiente Linux
neste processo de revisão e o container rodou depois em uma máquina Windows
com resultado idêntico (`total_amount=16084.20` nos dois casos). O que a
imagem **não** iguala é o ambiente do *host*: performance de I/O do volume
montado, comportamento do daemon Docker (Docker Desktop no Windows/macOS
roda em uma VM Linux por baixo, o que pode ter overheads diferentes de um
Docker Engine nativo no Linux), e configuração de rede do host.

### Desafio 5 — Declare o ambiente

**O que o `plan` torna visível antes da mudança acontecer?** A lista exata
de recursos que serão criados, alterados ou destruídos, com valores
conhecidos e marcados como `(known after apply)` quando dependem do
resultado da execução (como o `id` do container). Confirmado na prática:
`terraform plan` mostrou `4 to add, 0 to change, 0 to destroy` antes de
qualquer recurso existir — a pessoa vê o impacto completo antes de digitar
`yes`, sem surpresas.

**O que se perde e o que se preserva com `destroy` seguido de `apply`?**
Se perde: o container, a rede e o volume nomeado — recursos efêmeros que o
Terraform recria com IDs novos (confirmado: o `container_name` continuou
`ex2-dataops-pipeline`, mas o `id` interno do Docker mudou entre a criação
original e a recriação). Se preserva: a imagem Docker localmente cacheada
(por causa de `keep_locally = true`), e, mais importante, o **resultado**
gravado em `data/output/`, que fica no host via bind mount e não é gerenciado
pelo Terraform — não é destruído junto com a infraestrutura.

**O container é stateless. A saída do pipeline é stateful. Onde cada um deve
viver?** O container deve viver como um recurso descartável, recriável a
qualquer momento a partir da imagem (`docker_container.pipeline` no
Terraform, sem persistência própria). A saída deve viver fora do ciclo de
vida do container: no volume Docker nomeado (`docker_volume.output`) ou no
bind mount do host (`./data` no Compose), que sobrevivem independentemente
de quantas vezes o container for destruído e recriado.
