# EVIDÊNCIA — Exercício 02: do zero em Terraform

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Conta `325583868777` · usuário IAM `eda-grupo02` · executado em 2026-09-01
Terraform v1.15.8 · AWS CLI 2.34.54 · Athena engine v3

Bucket `eda-a08-lake-grupo02` · database `eda_a08_lake_grupo02` · tabela `corridas`
· workgroup `eda-a08-wg-grupo02` · teto `15728640`

As justificativas estão em `DECISOES.md`; aqui está a medição que as sustenta.

---

## 1. A execução, comando a comando

**Ambiente.** A conta estava limpa antes de começar, o que existir no fim é nosso,
e precisa sumir no `destroy`.

```
$ aws s3 ls | grep eda-a08                                   (nenhum)
$ aws glue get-databases --query 'DatabaseList[].Name' | grep eda_a08    (nenhum)
$ aws athena list-work-groups --query 'WorkGroups[].Name' | grep eda-a08 (nenhum)
```

**Gerar os dados.**

```
$ python ../dados/gerar-corridas.py --dias 8
dt=2026-09-01  16000 linhas  3.41 MB
dt=2026-08-31  16000 linhas  3.41 MB
... (8 dias, um arquivo por partição)
Pronto. 8 particoes em dados/saida/
```

**Aplicar.**

```
$ terraform init && terraform apply
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:
bucket_name    = "eda-a08-lake-grupo02"
database_name  = "eda_a08_lake_grupo02"
table_name     = "corridas"
teto_bytes     = 15728640
workgroup_name = "eda-a08-wg-grupo02"
```

Quinze recursos: 2 buckets + 2 bloqueios de acesso público + database + tabela +
workgroup (os 7 fixos) e 8 partições, uma por dia registrado.

**Ingerir.**

```
$ aws s3 cp ../dados/saida/ "s3://$(terraform output -raw bucket_name)/raw/corridas/" --recursive
[8 uploads]

$ aws s3 ls s3://eda-a08-lake-grupo02/raw/corridas/ --recursive --summarize
    3408477 raw/corridas/dt=2026-08-25/parte-0001.json
    3408169 raw/corridas/dt=2026-08-26/parte-0001.json
    3409209 raw/corridas/dt=2026-08-27/parte-0001.json
    3408021 raw/corridas/dt=2026-08-28/parte-0001.json
    3408631 raw/corridas/dt=2026-08-29/parte-0001.json
    3408841 raw/corridas/dt=2026-08-30/parte-0001.json
    3408647 raw/corridas/dt=2026-08-31/parte-0001.json
    3408870 raw/corridas/dt=2026-09-01/parte-0001.json

Total Objects: 8
   Total Size: 27268865
```

---

## 2. Os dados, medidos antes de decidir

Bytes exatos por partição e acumulado: é esta tabela que decide o teto:

```
dt=2026-08-25      3.408.477      acumulado    3.408.477
dt=2026-08-26      3.408.169      acumulado    6.816.646
dt=2026-08-27      3.409.209      acumulado   10.225.855
dt=2026-08-28      3.408.021      acumulado   13.633.876
dt=2026-08-29      3.408.631      acumulado   17.042.507
dt=2026-08-30      3.408.841      acumulado   20.451.348
dt=2026-08-31      3.408.647      acumulado   23.859.995
dt=2026-09-01      3.408.870      acumulado   27.268.865
```

Perfil dos campos, com as 128.000 linhas lidas uma a uma antes de qualquer deploy:

```
linhas totais ................ 128.000
JSON malformado .............. 0        (0,00%)
'valor' como string .......... 0        (0,00%)
'valor' com vírgula decimal .. 0        (0,00%)
tipos JSON de 'valor' ........ {'float': 128000}
faixa de 'valor' ............. 6.5 .. 58.0
formato de data_corrida ...... {'HH:MM:SS': 128000}
'fim' anterior ao início ..... 50.148   (39,18%)
```

O enunciado afirma que ~1,5% dos eventos mandam `"17,82"` com vírgula. **Neste
gerador isso não acontece:** zero em 128.000. Registramos porque muda o que a
DECISÃO 01 pode alegar ter medido.

---

## 3. As decisões, medidas

### O schema, lido da API do Glue (não do HCL)

```json
"colunas": [
  {"Name": "corrida_id",    "Type": "string"},
  {"Name": "motorista_id",  "Type": "string"},
  {"Name": "passageiro_id", "Type": "string"},
  {"Name": "bairro",        "Type": "string"},
  {"Name": "data_corrida",  "Type": "string"},          <- DECISÃO 02
  {"Name": "fim",           "Type": "string"},          <- DECISÃO 02
  {"Name": "distancia_km",  "Type": "double"},
  {"Name": "duracao_min",   "Type": "int"},
  {"Name": "valor",         "Type": "decimal(10,2)"}    <- DECISÃO 01
],
"particao":      [{"Name": "dt", "Type": "string"}],
"serde_tabela":  {"ignore.malformed.json": "false", "use.null.for.invalid.data": "false"},
"params_tabela": {"classification": "json",
                  "ignore.malformed.json": "false", "use.null.for.invalid.data": "false"}
```

E o SerDe da **partição**, que é o que a consulta realmente usa (DECISÃO 03):

```json
$ aws glue get-partition --partition-values 2026-09-01
{
  "location": "s3://eda-a08-lake-grupo02/raw/corridas/dt=2026-09-01/",
  "serde":    {"ignore.malformed.json": "false", "use.null.for.invalid.data": "false"},
  "valor":    [{"Name": "valor", "Type": "decimal(10,2)"}]
}
```

### DECISÃO 01 e 02, numa varredura só

```
$ SELECT count(*) AS linhas,
         count(try_cast(data_corrida AS timestamp)) AS viraram_timestamp,
         count(valor) AS valor_nao_nulo, sum(valor) AS soma_valor,
         min(valor) AS minimo, max(valor) AS maximo
  FROM corridas WHERE dt='2026-09-01'

ESTADO : SUCCEEDED
BYTES  : 3408870

linhas            | 16000
viraram_timestamp |     0        <- ZERO de 16.000 converteriam para timestamp
valor_nao_nulo    | 16000        <- decimal(10,2) leu 100%, sem um nulo
soma_valor        | 517959.19
minimo            | 6.50
maximo            | 58.00        <- zero final preservado: é decimal, não float
```

Amostra que mostra o formato do tempo e um `fim` anterior ao início:

```
corrida_id       | data_corrida | fim      | valor | distancia_km
c20260901000000  | 02:31:00     | 02:54:00 | 19.49 | 4.2
c20260901000001  | 22:04:00     | 22:10:00 | 37.33 | 16.1
c20260901000002  | 02:29:00     | 02:01:00 | 33.89 | 16.1   <- fim ANTES do início
c20260901000003  | 01:16:00     | 01:49:00 | 47.25 | 7.5
c20260901000004  | 04:43:00     | 04:53:00 | 29.73 | 9.6
```

### DECISÃO 04 — catálogo e dado são independentes

Entre o `apply` (que registra as partições) e o upload (que põe o dado lá) existe
uma janela em que as 8 partições apontam para pastas vazias. Medimos nela:

```
$ aws s3 ls s3://eda-a08-lake-grupo02/ --recursive | wc -l
0

$ aws glue get-partitions --database-name eda_a08_lake_grupo02 --table-name corridas
2026-08-25  2026-08-26  2026-08-27  2026-08-28
2026-08-29  2026-08-30  2026-08-31  2026-09-01

$ SELECT count(*) AS total FROM corridas
ESTADO : SUCCEEDED          <- teve SUCESSO
BYTES  : 0
total  : 0                  <- zero, sem erro, sem aviso
```

Depois do upload, a mesma consulta:

```
ESTADO : SUCCEEDED
BYTES  : 27268865           <- idêntico ao Total Size do S3
total  : 128000
```

Nada mudou no catálogo entre as duas medições, só o dado apareceu embaixo dele.
Quando catálogo e dado discordam, quem responde é o catálogo, em silêncio.

### O casamento `location` × chave real no S3

A rubrica do critério 3 exige que a `location` bata com a chave, mas o
`verifica.sh` só conta partições e procura a de hoje. Verificamos por fora:

```
dt=2026-08-25  CASA  raw/corridas/dt=2026-08-25/
dt=2026-08-26  CASA  raw/corridas/dt=2026-08-26/
dt=2026-08-27  CASA  raw/corridas/dt=2026-08-27/
dt=2026-08-28  CASA  raw/corridas/dt=2026-08-28/
dt=2026-08-29  CASA  raw/corridas/dt=2026-08-29/
dt=2026-08-30  CASA  raw/corridas/dt=2026-08-30/
dt=2026-08-31  CASA  raw/corridas/dt=2026-08-31/
dt=2026-09-01  CASA  raw/corridas/dt=2026-09-01/

8 partições no Glue · 8 prefixos no S3 · 0 divergências
```

---

## 4. DECISÃO 05 — o teto

O primeiro `apply` subiu com teto no topo útil (`117455962`), de propósito, para a
consulta larga rodar inteira e ser medida. Com o número na mão, fixamos `15728640`.

```
$ aws athena get-work-group --work-group eda-a08-wg-grupo02
+----------+----------+-------------------------------------------------+
|  cutoff  | enforce  |                      saida                      |
+----------+----------+-------------------------------------------------+
|  15728640|  True    |  s3://eda-a08-results-grupo02/athena-results/   |
+----------+----------+-------------------------------------------------+
```

As quatro consultas, com o freio no ar:

```
larga     8 dias   CANCELLED   15.728.640   Bytes scanned limit was exceeded
estreita  1 dia    SUCCEEDED    3.408.870   total = 16.000
controle  4 dias   SUCCEEDED   13.634.989   total = 64.000
controle  5 dias   CANCELLED   15.728.640   Bytes scanned limit was exceeded
```

A política declarada e a política observada são a mesma: até 4 dias passa, do 5º em
diante morre. O Athena **para de varrer ao atingir o corte** , por isso os dois casos
barrados reportam 15.728.640, e não os 27,3 MB ou 17,0 MB que teriam varrido.

A consulta de 4 dias varreu **13.634.989** bytes, 1.113 a mais que a soma dos
arquivos (13.633.876). Um teto colado na fronteira teria barrado o que pretendia
liberar; a folga de 2,09 MB absorve essa diferença.

---

## 5. O `verifica.sh`

Rodada final com a stack no ar:

```
Exercício 02 — verificação (região us-east-1, hoje 2026-09-01)
----------------------------------------------------------------
Critério 0 — Terraform, schema declarado, sem Crawler (ELIMINATÓRIO)
OK     [0]  requisito atendido (não pontua; libera o resto)
----------------------------------------------------------------
Critério 1 — os cinco outputs de contrato
       bucket_name = eda-a08-lake-grupo02
       database_name = eda_a08_lake_grupo02
       table_name = corridas
       workgroup_name = eda-a08-wg-grupo02
       teto_bytes = 15728640
PASSA  [1]  (10%)  os cinco outputs existem e estão preenchidos.
----------------------------------------------------------------
Critério 2 — schema declarado (≥8 colunas) e partição dt
       colunas declaradas: 9 · chave de partição: dt
PASSA  [2]  (25%)  schema com 9 colunas e partição dt.
----------------------------------------------------------------
Critério 3 — ≥3 partições, uma delas a de hoje
       partições registradas: 8 -> 2026-08-29 2026-08-25 2026-08-26 2026-08-30
                                   2026-08-28 2026-08-27 2026-08-31 2026-09-01
PASSA  [3]  (15%)  8 partições, incluindo a de hoje (2026-09-01).
----------------------------------------------------------------
Critério 4 — o teto mata a consulta larga e deixa passar a estreita
       teto declarado: 15728640 bytes
       larga:    estado=CANCELLED  motivo=Bytes scanned limit was exceeded
       estreita: estado=SUCCEEDED  bytes=3408870
FALHA  [4]  (15%)  larga_barrada=0 estreita_passou=1
----------------------------------------------------------------
Critério 6 — DECISOES.md (avaliação manual da justificativa)
       encontrei 6 decisões em ../DECISOES.md — o CONTEÚDO é avaliado à mão (20%).
----------------------------------------------------------------
Resumo dos critérios automáticos: 50 / 65 pontos-percentuais

Cole o bloco abaixo no seu PR:
  bucket=eda-a08-lake-grupo02  db=eda_a08_lake_grupo02  table=corridas
  wg=eda-a08-wg-grupo02  teto=15728640
  criterios_automaticos=50/65  data=2026-09-01T22:05:43Z
```

E o pós-destroy:

```
$ ./verifica.sh --pos-destroy
Critério 5 — destroy limpo
----------------------------------------------------------------
PASSA  [5]  (15%)  nenhum bucket órfão.
----------------------------------------------------------------
Critério 5: 15/15%
```

---

## 6. O destroy

```
$ terraform state list | wc -l                                    15
$ aws s3 ls s3://eda-a08-lake-grupo02/ --recursive | wc -l          8
$ aws s3 ls s3://eda-a08-results-grupo02/ --recursive | wc -l      20

$ terraform destroy
Destroy complete! Resources: 15 destroyed.
```

Os dois buckets saíram **com conteúdo dentro** — 8 objetos no lake e 20 resultados
de consulta no de results. Quem torna isso possível é o `force_destroy = true` que o
andaime já traz; sem ele o `destroy` trava em bucket não-vazio, que é o item nº 1 da
lista de "o que mais reprova".

O `--pos-destroy` só olha buckets S3, e a rubrica fala em "nenhum recurso órfão".
Varremos os três serviços:

```
buckets S3 eda-a08-*        : 0
databases Glue eda_a08_*    : 0
workgroups Athena eda-a08-* : 0
recursos no terraform state : 0
```

---

## 7. Três achados sobre o pacote

### 7.1 O `main.tf` distribuído não compila

O `terraform init` recusa o andaime antes de qualquer edição:

```
Error: Invalid single-argument block definition
  on main.tf line 75, in resource "aws_glue_catalog_table" "corridas":
  75:     columns { name = "corrida_id"    type = "string" }
```

Isolamos em dois passos, para provar que não era edição nossa. Primeiro, o
`main.tf` original copiado para uma pasta limpa dá o mesmo erro. Depois, expandindo
**um único** bloco, o erro anda para o seguinte:

```
  79:     columns { name = "motorista_id"  type = "string" }
```

**Causa raiz:** o HCL2 aceita no máximo um argumento em bloco de uma linha, e
`columns { name = ... type = ... }` tem dois. São 18 blocos assim: 9 na tabela e 9
na partição. Expandimos os 18 para a forma multilinha, que é exatamente o que
`terraform fmt` gera; nenhuma coluna, nome ou tipo mudou.

```
$ terraform init
Terraform has been successfully initialized!
$ terraform validate
Success! The configuration is valid.
```

### 7.2 O critério 4 do `verifica.sh` procura o estado errado

O script exige `estado == "FAILED"`:

```bash
larga_morreu="nao"; echo "$lmot" | grep -qiE "bytes|cutoff|exceed" && larga_morreu="sim"
[ "$lest" = "FAILED" ] && [ "$larga_morreu" = "sim" ] && larga_ok=1 || larga_ok=0
```

O que este Athena devolve no corte por `BytesScannedCutoffPerQuery` é **`CANCELLED`**,
com `StateChangeReason = "Bytes scanned limit was exceeded"`. A segunda condição casa
(`larga_morreu=sim`), a primeira não — e o script imprime `larga_barrada=0` na linha
seguinte à sua própria evidência de que o freio disparou.

O requisito do enunciado está atendido e medido: a larga morre por estouro de bytes,
a estreita responde. **Não alteramos o script.** Sugestão de correção, se for o caso:
aceitar os dois estados terminais que a AWS usa para corte,
`[ "$lest" = "FAILED" ] || [ "$lest" = "CANCELLED" ]`.

### 7.3 O critério 6 depende do locale de quem roda

Com o `DECISOES.md` no lugar, o script disse "achei só 0 decisões". O padrão é
`grep -ciE 'DECIS[ÃA]O\s*0?[1-5]'`. Mesmo arquivo, mesmo padrão, variando o locale:

```
LANG vazio          ->  0        LC_ALL=C.UTF-8      ->  6
LC_ALL=C            ->  0        LC_ALL=pt_BR.UTF-8  ->  6
```

Controle que confirma o mecanismo:

```
padrão 'DECIS.O\s*0?[1-5]'  (ponto)    ->  0
padrão 'DECISÃO\s*0?[1-5]'  (literal)  ->  6
```

**Causa raiz:** o `Ã` ocupa dois bytes em UTF-8 (`C3 83`). Sem locale UTF-8 o grep
opera byte a byte, e a classe `[ÃA]` vira o conjunto `{C3, 83, 41}`: casa o `C3`, mas
exige `O` em seguida, e o byte seguinte é `83`. Por isso até o `.` falha — ele casa um
byte, não um caractere.

Corrigimos no ambiente, não no script: `export LC_ALL=C.UTF-8`. Nenhum outro grep do
`verifica.sh` depende de acento, então os critérios 0 a 4 não foram afetados.

---

## 8. Como reproduzir

```bash
export AWS_PROFILE=eda AWS_REGION=us-east-1 LC_ALL=C.UTF-8
cd lab02/terraform
python ../dados/gerar-corridas.py --dias 8
terraform init && terraform apply
aws s3 cp ../dados/saida/ "s3://$(terraform output -raw bucket_name)/raw/corridas/" --recursive
cd ../verificacao && ./verifica.sh
cd ../terraform && terraform destroy
cd ../verificacao && ./verifica.sh --pos-destroy
```

As datas em `terraform.tfvars` são as do dia da execução (2026-08-25 a 2026-09-01).
Para reproduzir em outra data, regenere os dados e ajuste `dias_particao` para as
pastas `dt=` que o gerador criar — uma delas precisa ser a do dia corrente.
