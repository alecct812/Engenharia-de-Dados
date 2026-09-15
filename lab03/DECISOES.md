# DECISOES.md · Exercício 03: refatorar em módulo, com plan limpo

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Conta `325583868777` · executado em 2026-09-15 · Terraform v1.15.8

Backend `s3://eda-tfstate-grupo02/aula12/terraform.tfstate` · trava `eda-tflock`
· workspaces `default` (a stack) e `dev` (vazio)

Uma frase por decisão, e sob ela a medição que a sustenta. Falamos da refatoração,
não do lake: o lake é o mesmo do começo ao fim, e é esse o ponto. A evidência bruta
está em `EVIDENCIA.md`.

---

## DECISÃO 01: a fronteira do módulo, os seis recursos e nada além deles

Entraram no módulo os seis `resource` e só eles; ficaram na raiz o `provider` com
suas `default_tags`, as variáveis que o usuário preenche, o backend e o contrato de
outputs. **Aceitamos perder a autonomia do módulo**: ele não roda sozinho, porque não
declara provider nenhum, e quem o instancia precisa configurar a AWS por ele. É
exatamente o que queremos: um módulo que declara o próprio provider não pode ser
instanciado duas vezes com contas ou regiões diferentes, e é aí que módulo deixa de
ser reusável e vira cópia.

> **Medido.** O módulo recebe duas variáveis, `sufixo` e `teto_bytes`. `regiao` não
> entra, porque é do provider. Os outputs da raiz leem `module.lake.bucket_name`, e
> não `module.lake.aws_s3_bucket.lake.bucket`. A segunda forma funcionaria, mas
> prenderia a raiz ao nome interno do recurso, e quem consome um módulo não deveria
> precisar saber como ele se organiza por dentro.
>
> A checagem de que nada foi rebatizado, comparando o andaime original contra o
> módulo:
>
> ```
> $ diff <(grep -oE '^resource "[a-z_]+" "[a-z_]+"' main.tf.andaime) \
>        <(grep -oE '^resource "[a-z_]+" "[a-z_]+"' modules/lake/main.tf)
> (sem diferenças)
> ```

## DECISÃO 02: mover o estado com `terraform state mv`, seis comandos

Usamos `terraform state mv`, um por recurso, e **aceitamos perder o registro da
refatoração no código**: quem ler o repositório daqui a um mês não tem como saber
que esses recursos já viveram na raiz, porque a operação aconteceu no estado e não
deixou rastro no HCL. Com `moved {}` o histórico ficaria versionado junto com o
código e a reconciliação valeria para qualquer pessoa que rodasse `plan` depois,
mas ela também ficaria lá para sempre, e alguém teria que decidir quando remover. A
rubrica aceita os dois; escolhemos o que deixa o código limpo e resolve o estado de
uma vez, porque o estado aqui é único e remoto, e somos nós os únicos a operá-lo.

> **Medido.** Comparamos o estado antes e depois, recurso a recurso. Se algum `mv`
> tivesse recriado alguma coisa, o `id` mudaria:
>
> ```
> recurso                                  módulo antes  módulo depois  id igual?
> aws_athena_workgroup.wg                  (raiz)        module.lake    SIM
> aws_glue_catalog_database.db             (raiz)        module.lake    SIM
> aws_glue_catalog_table.corridas          (raiz)        module.lake    SIM
> aws_s3_bucket.lake                       (raiz)        module.lake    SIM
> aws_s3_bucket.results                    (raiz)        module.lake    SIM
> aws_s3_bucket_public_access_block.lake   (raiz)        module.lake    SIM
>
> 6/6 recursos com o MESMO id, nenhum objeto foi recriado
> ```
>
> **O único campo que mudou foi `module`**, de vazio para `module.lake`. O `state mv`
> reescreve o mapa, não o território: nenhuma chamada à AWS acontece, e é por isso
> que identificadores como `eda-a12-grupo02-lake` sobrevivem intactos: um bucket
> destruído e recriado não teria como manter o mesmo id.

## DECISÃO 03: workspace, e a stack fica no `default`

Criamos o workspace `dev` e mantivemos a stack no `default`, e **aceitamos que o
`dev` seja um espaço vazio que não isola nada de verdade**: os nomes dos recursos
saem de `var.sufixo` e não incluem `terraform.workspace`, então aplicar a mesma
configuração no `dev` tentaria criar `eda-a12-grupo02-lake`, um bucket que já
existe. Workspace só isola de fato quando o nome do ambiente entra no nome do
recurso; sem isso ele separa o estado e não a infraestrutura, o que é uma armadilha
pior que não ter workspace nenhum, porque parece isolamento.

Escolhemos workspace em vez de pasta separada porque a stack é **a mesma**
infraestrutura em ambientes diferentes, e não infraestruturas diferentes. Pasta
separada custa código duplicado e backend próprio; workspace compartilha o código e
separa só o estado. Quando as duas infraestruturas divergirem de verdade, aí pasta
passa a ser a resposta certa.

> **Medido.** Entramos no `dev` e perguntamos ao Terraform o que ele faria:
>
> ```
> $ terraform workspace select dev
> $ terraform state list | wc -l
> 0
> $ terraform plan -detailed-exitcode -var="sufixo=grupo02"
> Plan: 6 to add, 0 to change, 0 to destroy.       rc=2
> ```
>
> `6 to add`, e `rc=2`: se a stack vivesse no `dev`, o critério 1 cairia na hora.
> Repare que aqui é `0 to destroy`, e não `6 to destroy` como no passo anterior ao
> `state mv`: lá o estado conhecia os recursos e queria trocá-los de endereço; aqui
> ele não conhece nada, então só quer criar, e a criação colidiria com nomes que já
> existem.
>
> O `workspace_key_prefix` ficou visível no bucket, e só vale para os não-default:
>
> ```
> aula12/terraform.tfstate                12.4 KiB   <- default, key crua, 6 recursos
> eda-a12/dev/aula12/terraform.tfstate    181 Bytes  <- dev, com prefixo, vazio
> ```

## DECISÃO 04: o que o `plan` limpo prova, e o que não prova

O `plan` limpo prova uma coisa só, e vale ser exato sobre qual: **o código e o estado
descrevem a mesma infraestrutura**, logo a refatoração não recriou nada. **Aceitamos
que isso não é um atestado de saúde do lake**, e entender por que não foi o que mais
nos ensinou neste exercício.

O fechamento da aula diz que o `plan` não prova ausência de drift, porque compara o
código com o estado e não com a realidade. Fomos medir, e encontramos uma nuance: o
`plan` **refresca antes de comparar**. Cada linha `Refreshing state...` da nossa saída
é uma chamada real à AWS, então ele enxerga, sim, o que mudou lá fora.

A conclusão do slide continua certa, mas o limite é outro. O `plan` compara com a
realidade **dos recursos que ele gerencia, nos atributos que o provider sabe ler de
volta**. Fora desse recorte ele é cego, e são três buracos diferentes:

1. o recurso criado na mão não está no estado, então não entra na comparação;
2. o atributo que o provider não lê de volta pode divergir sem nunca aparecer;
3. a mudança feita depois do `plan` não existia no instante em que ele rodou.

O limite, portanto, não é de frescor: é de escopo. Um `plan` limpo diz "o que eu
gerencio está como foi declarado", e não "está tudo certo na conta".

> **Medido.** A saída do nosso `plan` limpo, com as chamadas de refresh visíveis:
>
> ```
> module.lake.aws_s3_bucket_public_access_block.lake: Refreshing state... [id=eda-a12-grupo02-lake]
> module.lake.aws_athena_workgroup.wg: Refreshing state... [id=eda-a12-grupo02-wg]
> module.lake.aws_glue_catalog_table.corridas: Refreshing state... [id=325583868777:eda_a12_grupo02:corridas]
>
> No changes. Your infrastructure matches the configuration.
> rc=0
> ```
>
> As linhas `Refreshing state...` são chamadas reais à AWS. O `rc=0` é o mesmo código
> que o `verifica.sh` lê no critério 1.

## DECISÃO 05: a ordem, mover o estado antes de aplicar

Se tivéssemos aplicado logo depois de embrulhar no módulo, o Terraform teria
destruído e recriado os seis recursos, e **aceitaríamos perder tudo o que estivesse
dentro deles em silêncio**: os dois buckets têm `force_destroy = true`, o que
significa que o `destroy` esvazia sem perguntar. Neste exercício o lake está vazio e
a perda seria só de identificadores; num lake com dado, a mesma sequência apagaria o
dado inteiro sem um aviso, e o `apply` terminaria com "sucesso".

O risco não é só perder conteúdo. A recriação com o **mesmo nome** é frágil: nome de
bucket S3 é global, e não fica disponível no instante seguinte à exclusão. É por isso
que o enunciado avisa que aplicar antes do `state mv` "às vezes deixa a stack meio
quebrada". Não é o pior caso, é o caso provável.

> **Medido.** É exatamente o que o `plan` pediu, antes do `state mv`:
>
> ```
> DESTRUIR (endereços antigos)             CRIAR (endereços novos)
> aws_athena_workgroup.wg                  module.lake.aws_athena_workgroup.wg
> aws_glue_catalog_database.db             module.lake.aws_glue_catalog_database.db
> aws_glue_catalog_table.corridas          module.lake.aws_glue_catalog_table.corridas
> aws_s3_bucket.lake                       module.lake.aws_s3_bucket.lake
> aws_s3_bucket.results                    module.lake.aws_s3_bucket.results
> aws_s3_bucket_public_access_block.lake   module.lake.aws_s3_bucket_public_access_block.lake
>
> Plan: 6 to add, 0 to change, 6 to destroy.
> ```
>
> A correspondência é 1 para 1 e o nome depois do prefixo é idêntico nas seis linhas.
> O Terraform não estava vendo recursos diferentes: estava vendo os mesmos recursos em
> endereços diferentes e, sem ser avisado, resolveria a diferença do jeito mais bruto
> disponível. **Não aplicamos.**

---

## Três observações sobre a execução

**O `main.tf` do andaime não compila.** Os três blocos
`columns { name = ... type = ... }` põem dois argumentos num bloco de uma linha, o
que o HCL2 não aceita, e o `terraform init` recusa o arquivo antes de qualquer coisa.
É o mesmo defeito que encontramos no Exercício 02, lá em dezoito blocos. A linha
imediatamente acima, `ser_de_info { serialization_library = ... }`, **não** dá erro,
ela tem um argumento só, o que isola a regra com precisão. Expandimos os três para a
forma multilinha, que é a que `terraform fmt` gera; nenhuma coluna, nome ou tipo
mudou. Neste exercício a correção tem um peso extra: precisava vir **antes** do
primeiro `apply`, porque depois qualquer alteração de atributo apareceria no `plan` e
derrubaria o critério 1.

**Versionamos o `.terraform.lock.hcl`, que o enunciado não mencionou.** O
`versions.tf` declara `version = "~> 5.0"`, uma faixa: hoje ela resolve para
5.100.0, e daqui a alguns meses pode resolver para outra. O lock file grava a
versão exata e os hashes dela, de modo que quem clonar o repositório e rodar
`terraform init` receba o mesmo provider que nós usamos. Num exercício cuja entrega
é literalmente "o `plan` está limpo", deixar a versão do provider em aberto é deixar
a prova em aberto junto: basta uma mudança de comportamento entre versões para o
`plan` de alguém deixar de fechar, sem ninguém ter tocado no código. São 1,4 KB, não
contém segredo nenhum, e é a recomendação da própria HashiCorp.

**O `dynamodb_table` que o exercício prescreve está deprecado.** O `init` avisa:
*"The parameter `dynamodb_table` is deprecated. Use parameter `use_lockfile`
instead."* O backend S3 passou a oferecer trava nativa, sem tabela nenhuma.
Mantivemos `dynamodb_table` porque é o que o enunciado e o `backend.hcl.example` do
pacote pedem, e porque não valia arriscar 30% do exercício por estética. O efeito
colateral aparece na saída do `verifica.sh`: o Terraform emite esse aviso no
**stdout**, e o script faz `workspace list 2>/dev/null`, que só descarta o stderr.
O texto do aviso acaba impresso junto com o nome do workspace na linha do critério 3.
O critério passa; a linha só fica feia.
