# EVIDÊNCIA · Exercício 03: refatorar em módulo, com plan limpo

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Conta `325583868777` · usuário IAM `eda-grupo02` · executado em 2026-09-15
Terraform v1.15.8 · provider AWS 5.100.0 · AWS CLI 2.34.54

Backend `s3://eda-tfstate-grupo02/aula12/terraform.tfstate` · trava `eda-tflock`
· workspaces `default` (a stack) e `dev` (vazio)

As justificativas estão em `DECISOES.md`. Aqui está a medição que as sustenta.

---

## 1. O backend da disciplina não existia

O Passo 1 do enunciado manda conferir que o backend está de pé. Não estava:

```
$ aws s3 ls s3://eda-tfstate-grupo02
NAO EXISTE
$ aws dynamodb describe-table --table-name eda-tflock
NAO EXISTE
```

Antes de criar qualquer coisa, procuramos de quem era a responsabilidade:

| Fonte | O que diz sobre o backend |
| --- | --- |
| Pacote do exercício (11 arquivos, conferido também dentro do `.zip`) | nenhum Terraform o cria; `backend.hcl.example` é só configuração |
| Os 8 slides da aula 12 | citam o backend, nunca nomeiam o bucket nem dizem quem cria |
| `lab01` (CloudFormation) | zero arquivos `.tf` ou `.hcl`, zero menções |
| `lab02` | *"Não existe backend.tf... não adicione backend aqui"*, proibido por design |
| Conta AWS | nenhum `eda-tfstate-*`, nenhum `eda-tflock` |

Descartamos a hipótese de tê-lo criado e destruído num exercício anterior: nunca
houve backend nenhum até aqui.

**O pacote se contradiz sobre o próprio nome do bucket.** O `enunciado.html` manda
rodar `aws s3 ls s3://eda-tfstate-$SUFIXO`, o que dá `eda-tfstate-grupo02`; o
`backend.hcl.example` traz `bucket = "eda-tfstate-CONTA"`, o que sugere o número da
conta. Seguimos o enunciado, porque é o comando que ele próprio manda executar. O
`verifica.sh` não checa o nome do bucket em lugar nenhum.

Provisionamos os dois pelo AWS CLI, **fora do Terraform do exercício**, que é o que a
rubrica e o slide 4 descrevem: *"o backend é o compartilhado da disciplina; não é
deste exercício e sobrevive ao destroy"*.

```
$ aws s3api create-bucket --bucket eda-tfstate-grupo02 --region us-east-1
$ aws s3api put-bucket-versioning --versioning-configuration Status=Enabled
Enabled
$ aws s3api put-bucket-encryption   (SSE-S3)
AES256
$ aws s3api put-public-access-block
{"BlockPublicAcls": true, "IgnorePublicAcls": true,
 "BlockPublicPolicy": true, "RestrictPublicBuckets": true}

$ aws dynamodb create-table --table-name eda-tflock \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
+--------+-------------------+--------------+-----------+
|  chave |     cobranca      |    nome      |  status   |
+--------+-------------------+--------------+-----------+
|  LockID|  PAY_PER_REQUEST  |  eda-tflock  |  CREATING |
+--------+-------------------+--------------+-----------+
$ aws dynamodb wait table-exists --table-name eda-tflock
ACTIVE
```

Confirmação de que ficaram fora do ciclo de vida do exercício:

```
$ grep -c 'tfstate\|tflock' terraform/main.tf
0
```

Versionamento e criptografia não foram pedidos pelo enunciado. O estado descreve a
infraestrutura inteira, e um estado corrompido sem versão anterior significa
reconstruir o mapa na mão; a seção 8 mostra esse versionamento valendo a pena.

---

## 2. A stack plana, o ponto de partida

```
$ terraform init && terraform apply -var="sufixo=grupo02"
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:
bucket_name    = "eda-a12-grupo02-lake"
database_name  = "eda_a12_grupo02"
table_name     = "corridas"
teto_bytes     = 20971520
workgroup_name = "eda-a12-grupo02-wg"
```

Os endereços no estado antes da refatoração, que é a foto que o `state mv` vai
reescrever:

```
$ terraform state list
aws_athena_workgroup.wg
aws_glue_catalog_database.db
aws_glue_catalog_table.corridas
aws_s3_bucket.lake
aws_s3_bucket.results
aws_s3_bucket_public_access_block.lake

terraform.tfstate local : 12.771 bytes
backend configurado     : nenhum (estado local, é o ponto de partida)
objetos em s3://eda-tfstate-grupo02 : 0
```

---

## 3. A refatoração do código, e o plan que ela produz

```
terraform/
|-- main.tf              agora só um  module "lake"
|-- outputs.tf           os 5 do contrato, lendo do módulo
|-- variables.tf         intocado
|-- providers.tf         intocado
|-- versions.tf          intocado
+-- modules/lake/
    |-- main.tf          os 6 resources, byte a byte iguais
    |-- variables.tf     sufixo, teto_bytes
    +-- outputs.tf       a fronteira de saída
```

O `backend.tf` ainda não existe nesta etapa: ele só entra na seção 5, depois do plan
limpo com o estado ainda local.

Verificação de que nada foi rebatizado, comparando o pacote original contra o módulo:

```
$ diff <(grep -oE '^resource "[a-z_]+" "[a-z_]+"' original/main.tf) \
       <(grep -oE '^resource "[a-z_]+" "[a-z_]+"' modules/lake/main.tf)
(sem diferenças)
```

Com o código em módulo e o estado ainda na raiz, o `plan` pede o pior:

```
$ terraform init
Initializing modules...
- lake in modules\lake
Terraform has been successfully initialized!

$ terraform plan -var="sufixo=grupo02"

DESTRUIR (endereços antigos)             CRIAR (endereços novos)
aws_athena_workgroup.wg                  module.lake.aws_athena_workgroup.wg
aws_glue_catalog_database.db             module.lake.aws_glue_catalog_database.db
aws_glue_catalog_table.corridas          module.lake.aws_glue_catalog_table.corridas
aws_s3_bucket.lake                       module.lake.aws_s3_bucket.lake
aws_s3_bucket.results                    module.lake.aws_s3_bucket.results
aws_s3_bucket_public_access_block.lake   module.lake.aws_s3_bucket_public_access_block.lake

Plan: 6 to add, 0 to change, 6 to destroy.
```

**A correspondência é 1 para 1 e o nome depois do prefixo é idêntico nas seis
linhas.** Isso prova duas coisas ao mesmo tempo: nenhum recurso foi rebatizado (se
tivesse sido, as listas não pareariam), e o Terraform não está vendo recursos
diferentes, está vendo os mesmos recursos em endereços diferentes. Sem ser avisado,
ele resolve a diferença do jeito mais bruto disponível.

Nenhuma mudança de output apareceu no plan. **Não aplicamos.**

---

## 4. O `state mv`, e por que a AWS não foi tocada

```
$ terraform state mv aws_s3_bucket.lake  module.lake.aws_s3_bucket.lake
Move "aws_s3_bucket.lake" to "module.lake.aws_s3_bucket.lake"
Successfully moved 1 object(s).
```

Seis vezes, uma por recurso. Comparamos o estado antes e depois, recurso a recurso:

```
recurso                                  módulo antes  módulo depois  id igual?
aws_athena_workgroup.wg                  (raiz)        module.lake    SIM
aws_glue_catalog_database.db             (raiz)        module.lake    SIM
aws_glue_catalog_table.corridas          (raiz)        module.lake    SIM
aws_s3_bucket.lake                       (raiz)        module.lake    SIM
aws_s3_bucket.results                    (raiz)        module.lake    SIM
aws_s3_bucket_public_access_block.lake   (raiz)        module.lake    SIM

6/6 recursos com o MESMO id
```

Os ids, para o registro:

```
aws_athena_workgroup.wg                eda-a12-grupo02-wg
aws_glue_catalog_database.db           325583868777:eda_a12_grupo02
aws_glue_catalog_table.corridas        325583868777:eda_a12_grupo02:corridas
aws_s3_bucket.lake                     eda-a12-grupo02-lake
aws_s3_bucket.results                  eda-a12-grupo02-results
aws_s3_bucket_public_access_block.lake eda-a12-grupo02-lake
```

O único campo que mudou no estado foi `module`, de vazio para `module.lake`. Os ids
iguais, sozinhos, não provam que nada foi recriado: o id destes recursos é o próprio
nome, e um bucket destruído e recriado com o mesmo nome voltaria com o mesmo id. Eles
mostram que cada recurso manteve a sua identidade no estado. O que garante que a AWS
não foi tocada é o procedimento: o `state mv` só reescreve o arquivo de estado, sem
nenhuma chamada à AWS, e nenhum `apply` foi executado entre o código movido e o plan
limpo da seção 5. Comparar a data de criação de cada recurso antes e depois seria uma
prova independente, mas não a registramos.

---

## 5. O plan limpo, local e depois remoto

Ainda com estado local:

```
$ terraform plan -detailed-exitcode -var="sufixo=grupo02"
No changes. Your infrastructure matches the configuration.
rc=0
```

O mesmo `plan` que pedia `6 to add, 6 to destroy` na seção 3 agora não pede nada, e
entre um e outro nenhum comando tocou a AWS.

A migração para o backend:

```
$ cat backend.tf
terraform {
  backend "s3" {
    workspace_key_prefix = "eda-a12"
  }
}

$ terraform init -migrate-state -force-copy -backend-config=backend.hcl
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

Usamos `-force-copy` porque a sessão não é interativa: é a flag que responde "yes"
à pergunta de copiar o estado local para o novo backend.

```
$ aws s3 ls s3://eda-tfstate-grupo02/ --recursive --human-readable
2026-09-15 09:34:30   12.4 KiB aula12/terraform.tfstate

$ ls -l terraform.tfstate
0 bytes                       (o migrate-state esvazia em vez de apagar)

$ terraform plan -detailed-exitcode -var="sufixo=grupo02"
No changes. Your infrastructure matches the configuration.
rc=0
```

A migração de backend também não recriou nada.

---

## 6. O workspace, e por que a stack fica no `default`

```
$ terraform workspace new dev
$ terraform workspace list
* default
  dev
```

Em vez de afirmar por que a stack não pode ir para o `dev`, medimos:

```
$ terraform workspace select dev
$ terraform state list | wc -l
0
$ terraform plan -detailed-exitcode -var="sufixo=grupo02"
Plan: 6 to add, 0 to change, 0 to destroy.       rc=2

$ terraform workspace select default
$ terraform state list | wc -l
6
$ terraform plan -detailed-exitcode -var="sufixo=grupo02"
No changes.                                      rc=0
```

Repare que no `dev` é `0 to destroy`, e não `6 to destroy` como na seção 3. Lá o
estado conhecia os recursos e queria trocá-los de endereço; aqui ele não conhece
nada, então só quer criar, e a criação colidiria com nomes que já existem.

O `workspace_key_prefix` ficou visível no bucket, e só vale para os não-default:

```
aula12/terraform.tfstate                12.4 KiB    default, key crua, 6 recursos
eda-a12/dev/aula12/terraform.tfstate    181 Bytes   dev, com prefixo, vazio
```

---

## 7. O `verifica.sh`

```
Exercício 03 — verificação da refatoração (região us-east-1)
----------------------------------------------------------------
Critério 0 — módulo + backend remoto + workspace (ELIMINATÓRIO)
OK     [0]  módulo, backend s3 e pasta modules/ presentes
----------------------------------------------------------------
Critério 1 — plan LIMPO (o coração do exercício)
PASSA  [1]  (30%)  No changes — a refatoração não recriou nada.
----------------------------------------------------------------
Critério 2 — o estado está no backend remoto
PASSA  [2]  (15%)  backend s3 configurado e sem estado local.
----------------------------------------------------------------
Critério 3 — um workspace nomeado foi usado
PASSA  [3]  (10%)  workspace(s) além do default: [...] dev
----------------------------------------------------------------
Critério 4 — os cinco outputs de contrato preservados
PASSA  [4]  (10%)  os cinco outputs continuam lá.
----------------------------------------------------------------
Critério 6 — DECISOES.md (avaliação manual)
       encontrei 5 decisões em ../DECISOES.md

Critérios automáticos: 65 / 65 pontos-percentuais
plan_limpo=sim  criterios_auto=65/65  data=2026-09-15T12:52:33Z
```

E depois do destroy:

```
Critério 5 — destroy limpo
----------------------------------------------------------------
PASSA  [5]  (15%)  nenhum bucket órfão.
Critério 5: 15/15%
```

A linha do critério 3 sai poluída, e a causa está na seção 9.3.

---

## 8. O destroy, e a sobrevivência do backend

```
$ terraform destroy -auto-approve -var="sufixo=grupo02"
module.lake.aws_athena_workgroup.wg: Destruction complete after 0s
module.lake.aws_s3_bucket_public_access_block.lake: Destruction complete after 0s
module.lake.aws_glue_catalog_table.corridas: Destruction complete after 0s
module.lake.aws_glue_catalog_database.db: Destruction complete after 1s
module.lake.aws_s3_bucket.lake: Destruction complete after 1s
module.lake.aws_s3_bucket.results: Destruction complete after 1s

Destroy complete! Resources: 6 destroyed.
```

O destroy operou sobre `module.lake.*`, não mais sobre a raiz: código, estado e
operação finalmente falam a mesma língua.

O slide 7 diz que a stack cai e o backend continua. Medimos os dois lados:

```
A STACK (tinha que sumir)             O BACKEND (tinha que continuar)
buckets eda-a12-grupo02-*  : 0        bucket eda-tfstate-grupo02 : DE PÉ
database eda_a12_grupo02   : removido tabela eda-tflock          : ACTIVE
workgroup ...-wg           : removido
```

É por isso que o backend precisava nascer fora do Terraform do exercício: se ele
fosse um dos recursos da stack, este `destroy` teria apagado o bucket que guarda o
próprio estado que estava sendo usado para saber o que apagar.

**O versionamento pagando a conta:**

```
$ aws s3api list-object-versions --bucket eda-tfstate-grupo02 --prefix aula12/terraform.tfstate
| atual | bytes  |           quando             |
|  True |  400   |  2026-09-15T13:26:30+00:00   |   vazio, depois do destroy
|  False|  12688 |  2026-09-15T12:34:30+00:00   |   com os 6 recursos
```

**A trava, limpa:**

```
$ aws dynamodb scan --table-name eda-tflock
itens totais : 2      travas ativas: 0

eda-tfstate-grupo02/aula12/terraform.tfstate-md5
eda-tfstate-grupo02/eda-a12/dev/aula12/terraform.tfstate-md5
```

Os dois itens são checksums, um por workspace, e são permanentes. A trava em si é um
item sem o sufixo `-md5`, que existe apenas durante uma operação; observamos uma no
`init`, que imprimiu `Releasing state lock`. Zero travas ativas significa que nenhuma
operação ficou pendurada.

---

## 9. Três achados sobre o pacote

### 9.1 O `main.tf` distribuído não compila

```
$ terraform init
Error: Invalid single-argument block definition

  on main.tf line 50, in resource "aws_glue_catalog_table" "corridas":
  50:     columns { name = "corrida_id" type = "string" }

A single-line block definition must end with a closing brace immediately
after its single argument definition.
```

O HCL2 aceita no máximo um argumento em bloco de uma linha, e os três `columns` têm
dois. A linha imediatamente acima, `ser_de_info { serialization_library = ... }`,
**não** dá erro, porque tem um argumento só: isso isola a regra com precisão.

Expandimos os três para a forma multilinha, que é a que `terraform fmt` gera; nenhuma
coluna, nome ou tipo mudou. É o mesmo defeito que encontramos no Exercício 02, lá em
dezoito blocos. Neste exercício a correção tinha que vir **antes** do primeiro
`apply`, porque depois qualquer alteração de atributo apareceria no `plan` e
derrubaria o critério 1.

### 9.2 O `dynamodb_table` que o exercício prescreve está deprecado

```
Warning: Deprecated Parameter
  on backend.tf line 17, in terraform:
  17:   backend "s3" {

The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile"
instead.
```

O backend S3 passou a oferecer trava nativa, sem tabela nenhuma. Mantivemos
`dynamodb_table` porque é o que o enunciado e o `backend.hcl.example` do pacote
pedem, e porque não valia arriscar 30% do exercício por estética de saída.

### 9.3 O critério 3 imprime o aviso junto com o nome do workspace

```
PASSA  [3]  (10%)  workspace(s) além do default: [texto do aviso] dev
```

O script faz:

```bash
ws="$(terraform -chdir="$TFDIR" workspace list 2>/dev/null | sed 's/[* ]//g' | ...)"
```

O `2>/dev/null` descarta o stderr, mas o Terraform emite o aviso de depreciação no
**stdout**, então ele entra na variável junto com o nome do workspace. O `grep`
seguinte encontra `dev` e o critério passa; apenas a linha impressa fica feia.

---

## 10. Como reproduzir

A pasta `lab03/terraform/` guarda a stack já refatorada, com o módulo e o
`backend.tf`. Para subi-la e rodar a verificação:

```bash
export AWS_PROFILE=eda AWS_REGION=us-east-1 SUFIXO=grupo02 LC_ALL=C.UTF-8

cd lab03/terraform
cp backend.hcl.example backend.hcl           # e preencha bucket com o seu
terraform init -backend-config=backend.hcl
terraform apply -var="sufixo=$SUFIXO"        # 6 recursos, estado no backend remoto
terraform workspace new dev && terraform workspace select default

cd ../verificacao && ./verifica.sh
cd ../terraform && terraform destroy -var="sufixo=$SUFIXO"
cd ../verificacao && ./verifica.sh --pos-destroy
```

Refazer o caminho da refatoração exige outro ponto de partida: a pasta `terraform/`
do pacote original, com a stack plana na raiz, sem `modules/`, sem `backend.tf` e com
estado local. A partir dela, na ordem das seções 2 a 6:

```bash
cd terraform                                 # a do pacote original
terraform init                               # depois de expandir os três columns (9.1)
terraform apply -var="sufixo=$SUFIXO"        # 6 recursos, estado local

# mova os recursos para modules/lake/ e deixe na raiz só o module "lake" (seção 3)
terraform init                               # instala o módulo
terraform state mv aws_s3_bucket.lake module.lake.aws_s3_bucket.lake   # e os outros 5
terraform plan -detailed-exitcode -var="sufixo=$SUFIXO"                # rc=0

# acrescente o backend.tf e o backend.hcl, e migre o estado (seção 5)
terraform init -migrate-state -force-copy -backend-config=backend.hcl
terraform workspace new dev && terraform workspace select default
```

Dali em diante, a verificação e o `destroy` seguem os três últimos comandos do bloco
anterior.

O `backend.hcl` não está versionado, porque nomeia a conta. O `.example` ao lado tem
a estrutura com um placeholder no lugar do nome do bucket.

O `LC_ALL=C.UTF-8` importa para o critério 6: o padrão do script é
`grep -ciE 'DECIS[ÃA]O...'`, e sem locale UTF-8 o grep opera byte a byte, de modo que
a classe `[ÃA]` não casa com o `Ã` de dois bytes. Descobrimos isso no Exercício 02.
