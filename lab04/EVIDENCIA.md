# EVIDÊNCIA · Exercício 04: a meta de custo, em Parquet particionado

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Conta `325583868777` · usuário IAM `eda-grupo02` · executado em 2026-10-21
Terraform v1.15.8 · provider AWS 5.100.0 · AWS CLI 2.34.54 · Python 3.13.15

Bucket `eda-a21-lake-grupo02` · database `eda_a21_grupo02` · tabela `trusted_corridas`
· job `eda-a21-trusted-grupo02` · workgroup `eda-a21-wg-grupo02`
Estado remoto em `s3://eda-tfstate-grupo02/aula21/grupo-02/terraform.tfstate`, trava `eda-tflock`

As justificativas estão em `DECISOES.md`; aqui está a medição que as sustenta, na
ordem em que foi feita. As saídas de comando são literais, com duas exceções:
caminhos locais desta máquina foram abreviados para `<raiz do pacote>` e
`<temp local>`, e trechos longos (o acompanhamento do job a cada 20 s, os relatórios
JSON do job) aparecem resumidos, com `...` marcando o que foi omitido. A transcrição
completa de cada passo fica no log bruto da execução.

---

## 1. Ambiente e pré-requisitos

### O `python3` desta máquina não executa nada

O `carregar-raw.sh` e o critério 4 do `verifica.sh` chamam `python3`. Neste Windows,
esse nome aponta para o atalho da Microsoft Store:

```
$ python3 -c 'import datetime as d; print(d.date.today() - d.timedelta(days=6))'
Python não foi encontrado; executar sem argumentos para instalar do Microsoft Store ...
```

Sem contorno, o gerador não produziria dado e o critério 4 rodaria a pergunta com a
mensagem de erro no lugar da data de corte. Reaproveitamos o shim escrito no Exercício
01 (`local/bin/python3`, que repassa para `python`), posto no PATH por um
`ambiente.sh`. Os dois são contorno local, ignorados pelo `.gitignore` do repositório,
e nenhum script do pacote foi alterado.

```
$ source ./ambiente.sh
python3 ....... <raiz do pacote>/local/bin/python3  (Python 3.13.15)
perfil AWS .... eda  (arn:aws:iam::325583868777:user/eda-grupo02)

$ python3 -c 'import datetime as d; print(d.date.today() - d.timedelta(days=6))'
2026-10-15
```

### Permissões

Este exercício cria um papel IAM e um job Glue, o que os anteriores não faziam. As
ações foram simuladas antes do `apply`:

```
$ aws iam simulate-principal-policy --policy-source-arn ...:user/eda-grupo02 ...
iam:CreateRole  iam:PutRolePolicy  iam:AttachRolePolicy  iam:PassRole  iam:DeleteRole
glue:CreateJob  glue:StartJobRun   glue:CreateTable      athena:CreateWorkGroup
(todas: allowed)
```

### O backend: reutilizado, não criado

```
bucket eda-tfstate-grupo02 : existe
tabela eda-tflock          : ACTIVE
chave aula21/grupo-02/     : sem uso anterior

eda-tfstate-325583868777   : não existe
```

O `backend.hcl.example` fornecido no pacote diz `eda-tfstate-CONTA`; como a turma
divide uma única conta e o bucket com o número da conta não existe, reaproveitou-se o
bucket do grupo, criado no Exercício 03. A discussão está nas observações do
`DECISOES.md`.

### Conta limpa antes de começar

```
bucket    eda-a21-lake-grupo02      não existe
job       eda-a21-trusted-grupo02   não existe
database  eda_a21_grupo02           não existe
workgroup eda-a21-wg-grupo02        não existe
papel     eda-a21-glue-grupo02      não existe
```

### Um problema de rede, isolado e contornado

Na rede em que a execução começou, a checagem do bucket travou. A investigação por
camada mostrou que DNS e S3 respondiam normalmente, mas que uma parte dos IPs de
entrada do S3 em `us-east-1` não aceitava conexão TCP em porta nenhuma, enquanto
outros IPs do mesmo bloco funcionavam. Como o DNS do S3 sorteia um IP por consulta,
cada chamada local ao S3 conectava, demorava cerca de 10 segundos ou travava. Glue,
Athena, IAM e DynamoDB respondiam normalmente.

```
                    rede inicial            rede alternativa
16.15.159.149       não conecta             tcp 0,159 s
16.15.163.111       não conecta             tcp 0,132 s
16.15.238.204       não conecta             tcp 0,125 s
52.217.232.58       tcp 10,4 s              tcp 0,121 s
54.231.168.178      tcp 10,5 s              tcp 0,145 s
```

Trocada a rede, os mesmos IPs passaram a conectar em menos de 0,2 s, e toda a
execução seguinte ocorreu na rede alternativa. O job Glue não seria afetado, já que lê
e grava o S3 de dentro da AWS.

---

## 2. Backend, variáveis e as três linhas do Parquet

```
$ cp backend.hcl.example backend.hcl            (eda-tfstate-grupo02, aula21/grupo-02)
$ cp terraform.tfvars.example terraform.tfvars  (turma 2026-2, owner act@cesar.school, sufixo grupo02)

$ terraform init -backend-config=backend.hcl
Successfully configured the backend "s3"!
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
Warning: Deprecated Parameter
The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile" instead.
Terraform has been successfully initialized!
```

Com as quatro decisões ainda nos valores do exemplo, o `plan` recusa, como o pacote
prevê:

```
$ terraform plan
Error: var.chaves_particao is empty list       A primeira chave precisa ser dt
Error: var.arquivos_por_pasta is 0              Entre 1 e 4 arquivos por pasta
Error: var.meta_bytes_madrugada is 0            A meta tem de caber em 1 MiB
Error: var.teto_bytes is 0                      O Athena recusa teto abaixo de 10 MiB
rc=1        (nenhum estado gravado no backend, nenhuma trava esquecida)
```

As três linhas que fazem a trusted ser Parquet vieram do `template.yaml` do Lab 05,
linhas 134, 135 e 137, conferidas caractere a caractere:

```diff
-    input_format  = ""
-    output_format = ""
+    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
+    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
     ser_de_info {
-      serialization_library = ""
+      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
     }
```

```
$ terraform fmt -check && terraform validate
Success! The configuration is valid.
```

---

## 3. Medição em duas fases: `["dt", "bairro"]` contra `["dt"]`

Para justificar a DECISÃO 01 com número próprio, construímos primeiro o layout
alternativo (fase M1) e depois o final (fase M2), sobre a mesma raw. Nas duas fases
as partições foram registradas por MSCK, para que a única variável fosse a chave de
partição. Meta e teto ficaram provisórios (1.048.576 e 209.715.200) até a seção 5,
para que nada fosse barrado durante a medição.

### A stack e a raw (uma vez só, servindo às duas fases)

```
$ terraform plan -out=m1.tfplan
Plan: 11 to add, 0 to change, 0 to destroy.

$ terraform apply m1.tfplan
Apply complete! Resources: 11 added, 0 changed, 0 destroyed.

$ ./carregar-raw.sh                                          (102 s)
destino ............. <temp local>\eda-a21\raw\corridas
objetos ............. 30  (um por partição dt=)
eventos ............. 518.400
bytes ............... 117.655.606
maior partição ...... dt=2026-10-18  3.922.560 bytes
Total Objects: 30
   Total Size: 117655606
```

### Fase M1: `["dt", "bairro"]`

```
$ ./rodar-job.sh                                             (265 s)
10:04:41  RUNNING
...
10:08:21  SUCCEEDED
{ "chaves": ["dt", "bairro"], "arquivos_por_pasta": 1,
  "linhas_raw": 518400, "linhas_trusted": 518400, "dias": 30,
  "pastas": 660, "arquivos": 660, "bytes": 24115255, "valor_nulo": 0, "ok": true }
MSCK REPAIR TABLE: ok

$ SELECT count(*), count(DISTINCT dt), count(DISTINCT bairro) FROM trusted_corridas
518400   30   22        (inclusive os bairros com acento e espaço no nome)
```

### Fase M2: `["dt"]`

A troca de chave, sozinha, seria uma atualização no lugar, e deixaria no catálogo as
660 partições de dois níveis da M1. Por isso a tabela foi recriada:

```
$ terraform plan                       (sem -replace)
  # aws_glue_catalog_table.trusted will be updated in-place
Plan: 0 to add, 2 to change, 0 to destroy.

$ terraform plan -replace=aws_glue_catalog_table.trusted -out=m2.tfplan
  # aws_glue_catalog_table.trusted will be replaced, as requested
  # aws_glue_job.trusted will be updated in-place
      ~ "--CHAVES" = "dt,bairro" -> "dt"
Plan: 1 to add, 1 to change, 1 to destroy.

$ terraform apply m2.tfplan
Apply complete! Resources: 1 added, 1 changed, 1 destroyed.
chaves: dt     partições registradas: 0

$ ./rodar-job.sh                                             (162 s)
{ "chaves": ["dt"], "arquivos_por_pasta": 1,
  "linhas_raw": 518400, "linhas_trusted": 518400, "dias": 30,
  "pastas": 30, "arquivos": 30, "bytes": 18143089, "valor_nulo": 0, "ok": true }
MSCK REPAIR TABLE: ok

$ aws s3 ls .../trusted/corridas/ --recursive | grep -c 'bairro='
0                       <- o modo overwrite do job apagou o layout anterior
```

### A pergunta da madrugada nas duas fases

```sql
SELECT bairro, count(*) AS corridas, round(sum(valor), 2) AS receita
FROM trusted_corridas
WHERE dt >= '2026-10-15' AND faixa_hora BETWEEN 0 AND 5
GROUP BY bairro ORDER BY corridas DESC;
```

Cada consulta rodou duas vezes; a primeira paga o aquecimento do motor e os bytes
lidos foram idênticos nas duas.

```
M1 ["dt","bairro"]   SUCCEEDED   613.639 B   motor 1.170 ms
M2 ["dt"]            SUCCEEDED   355.803 B   motor   835 ms

bairro          corridas   receita
Boa Viagem      2088       33461.87
Pina             814       12876.37
Recife Antigo    682       11405.62
...
(22 linhas, 11.137 corridas, 180.868,80 de receita nas duas fases)
```

### Os arquivos e os rodapés

O comprimento do rodapé de um arquivo Parquet fica nos seus 8 últimos bytes (4 bytes
de comprimento e a marca `PAR1`). Foram lidos apenas esses 8 bytes de cada arquivo
aberto pela pergunta, com `aws s3api get-object --range bytes=-8`.

```
                                       M1 ["dt","bairro"]      M2 ["dt"]
arquivos na trusted                    660                     30
tamanho dos arquivos                   16,4 a 127,1 KB         589,6 a 591,7 KB
                                       (média 35,7 KB)         (média 590,6 KB)
arquivos abertos pela pergunta         154                     7
rodapé de cada arquivo                 1.839 a 1.882 B         2.078 B
rodapés lidos pela pergunta            286.848 B               14.602 B
                                       (47% da leitura)        (4% da leitura)
dado lido (Data scanned - rodapés)     326.791 B               341.201 B
Data scanned da pergunta               613.639 B               355.803 B
consulta larga do critério 5           22.530.409 B            17.727.527 B
```

A partição por bairro deixa de ler a coluna `bairro`, mas com 22 valores ela quase não
pesa comprimida: o dado lido ficou parecido nas duas fases, e a diferença inteira está
nos 147 rodapés a mais.

### O erro que não dá erro

A mesma pergunta, filtrando pela coluna de dentro do arquivo em vez da chave do
caminho:

```
WHERE date(inicio) >= date '2026-10-15' AND faixa_hora BETWEEN 0 AND 5
SUCCEEDED   4.472.250 B        22 linhas, 11.137 corridas
```

Mesma resposta, 12,6 vezes mais leitura: sem a data no caminho, o Athena não poda
pasta nenhuma e abre os 30 arquivos.

---

## 4. DECISÃO 05: partition projection

### O "dia 31" de quem registra por MSCK e esquece de rodar

Na tabela registrada por MSCK, removemos do catálogo apenas a partição do dia
corrente. O arquivo continuou no S3, que é a situação de um dia novo que chegou e
ainda não foi registrado.

```
antes          30 partições   518.400 / 30 dias   madrugada 11.137   180.868,80

$ aws glue delete-partition --partition-values 2026-10-21
$ aws s3 ls .../trusted/corridas/dt=2026-10-21/        (1 arquivo parquet, intacto)

depois         29 partições   501.120 / 29 dias   madrugada  9.546   155.081,64
               estado SUCCEEDED   Data scanned 237.902 B

$ MSCK REPAIR TABLE trusted_corridas
Partitions not in metastore:  trusted_corridas:dt=2026-10-21
Repair: Added partition to metastore trusted_corridas:dt=2026-10-21
```

A consulta teve sucesso e respondeu 14% a menos, sem erro nem aviso; e, com a
leitura menor, a meta de custo continuaria cumprida com a resposta errada.

### A troca para a projeção

```hcl
projecao = merge(
  {
    "projection.enabled"          = "true"
    "projection.dt.type"          = "date"
    "projection.dt.format"        = "yyyy-MM-dd"
    "projection.dt.range"         = "2026-01-01,NOW"
    "projection.dt.interval"      = "1"
    "projection.dt.interval.unit" = "DAYS"
    "storage.location.template"   = local.template_caminho
  },
  contains(var.chaves_particao, "bairro") ? {
    "projection.bairro.type"   = "enum"
    "projection.bairro.values" = join(",", local.bairros)
  } : {}
)
```

```
$ terraform plan -replace=aws_glue_catalog_table.trusted
  + "projection.dt.range"       = "2026-01-01,NOW"
  + "storage.location.template" = "s3://eda-a21-lake-grupo02/trusted/corridas/dt=${dt}"
  (nenhum parâmetro projection.bairro)
Plan: 1 to add, 0 to change, 1 to destroy.

$ terraform apply
Apply complete! Resources: 1 added, 0 changed, 1 destroyed.
```

A tabela foi recriada para começar sem nenhuma partição registrada:

```
partições registradas no catálogo     0
projection.enabled                    true

SELECT count(*), count(DISTINCT dt)   518400   30
pergunta da madrugada                 SUCCEEDED   355.803 B   22 linhas, 11.137 corridas
```

Com o catálogo vazio, os 30 dias aparecem e a pergunta lê os mesmos bytes do layout
registrado por MSCK: a projeção muda como as pastas são encontradas, não quanto se lê.

---

## 5. DECISÕES 03 e 04: a meta e o teto

```
meta_bytes_madrugada = 524288       (512 KiB)
teto_bytes           = 10485760     (10 MiB)

$ terraform plan
  # aws_athena_workgroup.wg will be updated in-place
      ~ bytes_scanned_cutoff_per_query = 209715200 -> 10485760
Plan: 0 to add, 1 to change, 0 to destroy.

$ terraform apply
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.

$ aws athena get-work-group --work-group eda-a21-wg-grupo02
cutoff 10485760   enforce True
```

A fronteira do teto, com a mesma consulta de todas as colunas do critério 5:

```
todas as colunas, 17 dias (dt >= 2026-10-05)   SUCCEEDED   10.045.467 B
todas as colunas, 18 dias (dt >= 2026-10-04)   CANCELLED   10.485.760 B   Bytes scanned limit was exceeded
todas as colunas, 30 dias                      CANCELLED   10.485.760 B   Bytes scanned limit was exceeded
pergunta da madrugada                          SUCCEEDED      355.803 B
```

---

## 6. O pipeline final, de ponta a ponta, e o `verifica.sh`

O estado final foi alcançado trocando o registro depois do job (MSCK durante a
medição, projeção depois). Para provar que o código entregue funciona na ordem do
pacote, rodamos o job mais uma vez já com a projeção ligada:

```
$ ./rodar-job.sh             (257 s)
...
{ "chaves": ["dt"], "linhas_trusted": 518400, "dias": 30, "arquivos": 30,
  "bytes": 18143089, "valor_nulo": 0, "ok": true }
>> [3/3] registro das particoes
partition projection ligada: o Athena calcula as pastas, nada a registrar.

partições registradas no catálogo depois do job: 0
```

O script pulou o MSCK, o catálogo continuou vazio, e o job regravou os mesmos
18.143.089 bytes. Em seguida, o verificador:

```
$ ./verificacao/verifica.sh

Exercício 04 — verificação (região us-east-1)
----------------------------------------------------------------
Critério 0 — Terraform com backend remoto, trusted em Parquet (ELIMINATÓRIO)
OK     [0]  backend s3 e trusted em Parquet
----------------------------------------------------------------
Critério 1 — a trusted está declarada e particionada por data
PASSA  [1]  (15%)  partição: dt · 10 colunas + 1 chave(s) = as 10 colunas e o dt.
----------------------------------------------------------------
Critério 2 — a trusted tem os 30 dias, sem perder corrida
PASSA  [2]  (10%)  518400 corridas em 30 dias.
----------------------------------------------------------------
Critério 3 — no máximo 4 arquivos por pasta de partição
PASSA  [3]  (10%)  30 arquivos, no máximo 1 por pasta, 18143089 bytes no total.
----------------------------------------------------------------
Critério 4 — a pergunta da madrugada (7 dias) cabe na META declarada
       meta declarada: 524288 bytes · Data scanned: 355803 bytes · corridas: 11137
PASSA  [4]  (25%)  leu 355803 bytes, dentro da meta de 524288. Resposta certa: 11137 corridas.
----------------------------------------------------------------
Critério 5 — o teto do workgroup existe e barra a consulta larga
PASSA  [5]  (10%)  teto de 10485760 bytes: a consulta de todas as colunas foi barrada (CANCELLED).
       Bytes scanned limit was exceeded
----------------------------------------------------------------
Critério 7 — DECISOES.md (avaliação manual)
       encontrei 6 decisões em <raiz do pacote>/DECISOES.md — o conteúdo é avaliado à mão (20%).
----------------------------------------------------------------
Critérios automáticos: 70 / 70 pontos-percentuais
       faltam o critério 6 (./verificacao/verifica.sh --pos-destroy) e o 7 (manual).

Cole no seu PR:
  particao=dt  arquivos=30  meta=524288  lido_madrugada_7d=355803  teto=10485760  criterios_auto=70/70  data=2026-10-21T14:37:27Z
```

O critério 2 passou com o catálogo sem nenhuma partição registrada: quem encontrou
os 30 dias foi a projeção.

---

## 7. O destroy

```
$ terraform state list | wc -l                                   11
$ aws s3 ls s3://eda-a21-lake-grupo02/ --recursive | wc -l      121

$ terraform -chdir=terraform destroy
aws_athena_workgroup.wg: Destruction complete after 1s
aws_s3_bucket_public_access_block.lake: Destruction complete after 1s
aws_glue_job.trusted: Destruction complete after 1s
aws_iam_role_policy.glue_bucket: Destruction complete after 1s
aws_iam_role_policy_attachment.glue_service: Destruction complete after 1s
aws_s3_object.script: Destruction complete after 0s
aws_glue_catalog_table.raw: Destruction complete after 1s
aws_glue_catalog_table.trusted: Destruction complete after 1s
aws_glue_catalog_database.lake: Destruction complete after 0s
aws_iam_role.glue: Destruction complete after 0s
aws_s3_bucket.lake: Destruction complete after 3s
Destroy complete! Resources: 11 destroyed.
```

O bucket saiu com 121 objetos dentro (raw, trusted, script, relatório e os
resultados das consultas): é o `force_destroy` do pacote que permite isso.

```
$ ./verificacao/verifica.sh --pos-destroy
Critério 6 — destroy limpo
----------------------------------------------------------------
PASSA  [6]  (10%)  nenhum recurso eda-a21-*-grupo02 sobrou.
----------------------------------------------------------------
Critério 6: 10/10%
```

O `--pos-destroy` confere cinco nomes. Varremos também o que ele não olha:

```
bucket eda-a21-lake-grupo02          removido
job eda-a21-trusted-grupo02          removido
database eda_a21_grupo02             removido
workgroup eda-a21-wg-grupo02         removido
papel eda-a21-glue-grupo02           removido (e com ele as políticas ligadas)
recursos no estado do Terraform      0
```

**O backend sobreviveu, como deve.** O bucket `eda-tfstate-grupo02` e a tabela
`eda-tflock` continuam de pé. O versionamento do bucket guardou uma versão do estado
por `apply`, e a última, depois do destroy:

```
2026-10-21T13:02:41   23930 bytes    apply da fase M1
2026-10-21T13:15:14   24377 bytes    troca para ["dt"] (fase M2)
2026-10-21T13:29:32   24768 bytes    troca para a projeção
2026-10-21T13:44:52   24735 bytes    meta e teto definitivos
2026-10-21T14:38:39     845 bytes    depois do destroy
```

**A tabela de trava é da turma, e ficou intacta.** A `eda-tflock`, criada no
Exercício 03, hoje registra o estado de vários grupos da conta. O destroy deste
exercício não tocou em nenhum registro alheio:

```
registros antes do destroy                         22
registros depois do destroy                        22
registros de outros grupos alterados ou sumidos     0
travas ativas                                       0
```

```
$ rm -rf /tmp/eda-a21                (a cópia local da raw, como o passo 12 pede)
```

### Custo

```
job Glue, execução de 10:05     182 s cobrados   2 DPU   0,1011 DPU-h   US$ 0,0445
job Glue, execução de 10:15     106 s cobrados   2 DPU   0,0589 DPU-h   US$ 0,0259
job Glue, execução de 11:32     257 s de relógio (tempo cobrado não lido antes do destroy)
```

As duas primeiras execuções custaram US$ 0,07, medidos. A terceira teve duração de
relógio parecida com a primeira, o que leva o total do Glue a cerca de US$ 0,11
(estimado). O Athena e o S3 somam frações de centavo. O teto do exercício é US$ 1,00.

---

## 8. Achados sobre o pacote e o ambiente

**O andaime compila sem ajuste.** Nos Exercícios 02 e 03 o `main.tf` distribuído tinha
blocos `columns` de uma linha com dois argumentos, que o HCL2 recusa. Neste pacote as
colunas são geradas por `dynamic "columns"` a partir de um `locals`, e o defeito não
existe mais.

**Trocar `chaves_particao` não limpa o catálogo.** Para o Terraform, a mudança de chave
é uma atualização no lugar. Com partições já registradas por MSCK, a tabela ficaria com
partições de dois níveis sob uma chave só. O `-replace` da tabela resolve; com a
projeção, a questão desaparece, porque não há partição registrada.

**O critério 7 conta títulos, não conteúdo.** Com o modelo do pacote ainda no lugar, o
`verifica.sh` já encontrava "5 decisões", porque o modelo traz os títulos "DECISÃO 01" a
"DECISÃO 05". O conteúdo, que vale 20%, é avaliado à mão.

**O `dynamodb_table` do exemplo está deprecado.** O `init` avisa que o parâmetro cedeu
lugar a `use_lockfile`, a trava nativa do backend S3. Mantivemos o que o
`backend.hcl.example` prescreve, como no Exercício 03.

**O AWS CLI escreve em cp1252 no Windows.** Para medir os rodapés, a listagem do S3
foi lida por um script Python, que quebrou no `á` de `Caxangá` (o CLI emitia o byte
`e1`). A variável `PYTHONIOENCODING` não resolve; `PYTHONUTF8=1` faz o CLI emitir UTF-8:

```
sem nada            ... 6e 67 e1
PYTHONIOENCODING    ... 6e 67 e1
PYTHONUTF8=1        ... 6e 67 c3 a1
```

---

## 9. Como reproduzir

```bash
export AWS_PROFILE=eda AWS_REGION=us-east-1 LC_ALL=C.UTF-8
# no Windows, se python3 for o atalho da Microsoft Store, ver a seção 1
cd terraform
cp backend.hcl.example backend.hcl              # bucket e chave do grupo
cp terraform.tfvars.example terraform.tfvars    # sufixo, turma, owner e as quatro decisões:
#   chaves_particao = ["dt"]   arquivos_por_pasta = 1
#   meta_bytes_madrugada = 524288   teto_bytes = 10485760
terraform init -backend-config=backend.hcl
terraform apply
cd ..
./carregar-raw.sh
./rodar-job.sh                # com a projeção ligada, o script pula o MSCK
./verificacao/verifica.sh
terraform -chdir=terraform destroy
./verificacao/verifica.sh --pos-destroy
```

O gerador termina a janela no dia corrente, e o `verifica.sh` calcula a data de corte
também a partir dele: do `carregar-raw.sh` ao `verifica.sh`, tudo precisa acontecer no
mesmo dia, ou a contagem deixa de fechar 11.137.
