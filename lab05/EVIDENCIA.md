# EVIDENCIA.md · Exercício 05: o pipeline que pode rodar de novo

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1` · executado em 2026-11-04

A execução na ordem em que foi feita, com a saída dos comandos sem edição. O estado ficou
no backend remoto do Exercício 04 (`eda-tfstate-grupo02`, trava `eda-tflock`), com a chave
`aula-25/grupo02/terraform.tfstate`. O apply e o destroy foram feitos a partir de um
`terraform plan -out` revisado antes de aplicar.

Ordem: apply, plan limpo, carga da raw, atraso medido na raw, job (1ª execução), consulta,
job (2ª execução, o mesmo comando), consulta, `verifica.sh` (que roda o job pela 3ª vez),
backfill de 2026-11-01, destroy e `verifica.sh --pos-destroy`.

## terraform apply
```
aws_glue_catalog_database.lake: Creation complete after 2s [id=325583868777:eda_a25_grupo02]
aws_iam_role.job: Creation complete after 2s [id=eda-a25-grupo02-glue]
aws_iam_role_policy_attachment.glue: Creation complete after 0s [id=eda-a25-grupo02-glue-20261104120905910000000001]
aws_glue_catalog_table.corridas: Creation complete after 0s [id=325583868777:eda_a25_grupo02:corridas]
aws_glue_catalog_table.raw: Creation complete after 0s [id=325583868777:eda_a25_grupo02:raw_corridas]
aws_s3_bucket.lake: Creation complete after 4s [id=eda-a25-lake-grupo02]
aws_s3_object.script: Creation complete after 0s [id=scripts/pipeline-corridas.py]
aws_iam_role_policy.bucket: Creation complete after 0s [id=eda-a25-grupo02-glue:bucket-rw]
aws_glue_job.pipeline: Creation complete after 1s [id=eda-a25-grupo02-pipeline]
aws_athena_workgroup.wg: Creation complete after 1s [id=eda-a25-grupo02-wg]
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.
```
## Argumentos do job (aws glue get-job)
```
{
    "--BUCKET": "eda-a25-lake-grupo02",
    "--TABELA": "corridas",
    "--DIAS": "todos",
    "--MODO": "sobrescrever",
    "--job-bookmark-option": "job-bookmark-disable",
    "--job-language": "python",
    "--CHAVE": "corrida_id",
    "--JANELA": "3"
}
```
## plan logo depois do apply
```
No changes. Your infrastructure matches the configuration.
```

## ./carregar-raw.sh
```
hoje (última pasta) .... dt=2026-11-04
dado atrasado .......... 1.591 corridas da madrugada de 2026-11-01
                         saíram de dt=2026-11-01/ e chegaram em dt=2026-11-04/parte-0002-atrasadas.json
reentrega .............. 17.280 corridas de 2026-10-30 chegaram de novo em dt=2026-10-31/parte-0002-reenvio.json

as linhas para o Athena, prontas para copiar:
    WHERE dt >= '2026-10-29'          -- os últimos 7 dias
    WHERE dt = '2026-11-01'      -- o dia da madrugada atrasada

>> sincronizando com s3://eda-a25-lake-grupo02/raw/
Total Objects: 32
   Total Size: 121612198
```
## Atraso medido na raw (Athena): atraso = dt de chegada menos dia do evento
```
SELECT date_diff('day', date(substr(data_corrida,1,10)), date(dt)) AS atraso_dias, count(*), count(DISTINCT corrida_id), min/max dia do evento FROM raw_corridas GROUP BY 1
atraso_dias	corridas	distintas	dia_evento_min	dia_evento_max
0	516809	516809	2026-10-06	2026-11-04
1	17280	17280	2026-10-30	2026-10-30
3	1591	1591	2026-11-01	2026-11-01
(bytes lidos: 121612198)

SELECT count(*), count(DISTINCT corrida_id) FROM raw_corridas
535680	518400
```

## ./rodar-job.sh (1ª execução)
```
>> disparando eda-a25-grupo02-pipeline com {}
09:11:42  RUNNING
09:12:04  RUNNING
09:12:26  RUNNING
09:12:48  RUNNING
09:13:10  RUNNING
09:13:33  RUNNING
09:13:55  RUNNING
09:14:17  RUNNING
09:14:40  RUNNING
09:15:03  SUCCEEDED
{
  "tabela": "corridas",
  "modo": "sobrescrever",
  "janela": 3,
  "dias": "todos",
  "chave": "corrida_id",
  "linhas_lidas_da_raw": 535680,
  "fora_da_janela": 0,
  "duplicatas_removidas": 17280,
  "linhas_gravadas_neste_run": 518400,
  "dias_gravados_neste_run": 30,
  "linhas_na_tabela": 518400,
  "corridas_distintas_na_tabela": 518400
}
```
## Athena depois da 1ª execução
```
madrugada 7d (dt >= '2026-10-29', faixa_hora 0 a 5): 11137 (bytes lidos: 3889)
count(*), count(DISTINCT corrida_id): 518400 518400
por dia, 2026-10-29 a 2026-11-04: 17280 em cada um dos 7 dias
arquivo em dt=2026-11-01: 2026-11-04 09:15:01 607433 part-00000-5eaf459b-c7ab-43d8-8ab6-6b7b1cdbc044.c000.snappy.parquet
```

## ./rodar-job.sh (2ª execução, mesmo comando)
```
>> disparando eda-a25-grupo02-pipeline com {}
09:16:46  RUNNING
09:17:08  RUNNING
09:17:30  RUNNING
09:17:53  RUNNING
09:18:15  RUNNING
09:18:38  RUNNING
09:19:01  RUNNING
09:19:24  RUNNING
09:19:46  SUCCEEDED
{
  "tabela": "corridas",
  "modo": "sobrescrever",
  "janela": 3,
  "dias": "todos",
  "chave": "corrida_id",
  "linhas_lidas_da_raw": 535680,
  "fora_da_janela": 0,
  "duplicatas_removidas": 17280,
  "linhas_gravadas_neste_run": 518400,
  "dias_gravados_neste_run": 30,
  "linhas_na_tabela": 518400,
  "corridas_distintas_na_tabela": 518400
}
```
## Athena depois da 2ª execução
```
madrugada 7d: 11137 (bytes lidos: 3889)
count(*), count(DISTINCT corrida_id): 518400 518400
arquivo em dt=2026-11-01: 2026-11-04 09:19:44 607433 part-00000-ee912358-1c36-4a14-9b98-4c4f8eaf2d14.c000.snappy.parquet (trocado; antes 5eaf459b, 09:15:01)
trusted inteira: Total Objects: 30, Total Size: 18228296
```

## ./verificacao/verifica.sh
```
OK     [0]  (elimina)  backend remoto s3 e trusted em Parquet
PASSA  [1]  (20%)  a madrugada de 7 dias tem 11137 corridas, incluindo as atrasadas
       rodando o job mais uma vez (~3 min) para o critério 2…
PASSA  [2]  (25%)  rodar de novo não mudou nada: 518400 linhas e 11137 na madrugada, antes e depois
PASSA  [3]  (15%)  uma linha por corrida: 518400 linhas, 518400 corridas distintas
PASSA  [4]  (10%)  terraform plan limpo: o segundo apply não mudaria nada

Critérios automáticos: 70 / 70 pontos-percentuais
Falta o que o script não mede: o critério 5 (rode com --pos-destroy depois do destroy) e o DECISOES.md (20%).

evidência: sufixo=grupo02 hoje=2026-11-04 madrugada_7d=11137->11137 linhas=518400->518400 distintas=518400 {"chave_dedup":"corrida_id","janela_atraso_dias":3,"modo_escrita":"sobrescrever"}
```

## Backfill: ./rodar-job.sh DIAS=2026-11-01
```
>> disparando eda-a25-grupo02-pipeline com {"--DIAS":"2026-11-01"}
09:26:11  RUNNING
09:26:33  RUNNING
09:26:56  RUNNING
09:27:18  RUNNING
09:27:40  RUNNING
09:28:03  SUCCEEDED
{
  "tabela": "corridas",
  "modo": "sobrescrever",
  "janela": 3,
  "dias": "2026-11-01",
  "chave": "corrida_id",
  "linhas_lidas_da_raw": 535680,
  "fora_da_janela": 0,
  "duplicatas_removidas": 0,
  "linhas_gravadas_neste_run": 17280,
  "dias_gravados_neste_run": 1,
  "linhas_na_tabela": 518400,
  "corridas_distintas_na_tabela": 518400
}
```
### trusted antes x depois (diff do aws s3 ls --recursive, 30 linhas em cada)
```
27c27
< 2026-11-04 09:24:52     607433 trusted/corridas/dt=2026-11-01/part-00000-559d3189-390e-40f0-91e5-f96dbbac0e70.c000.snappy.parquet
---
> 2026-11-04 09:28:15     606302 trusted/corridas/dt=2026-11-01/part-00000-23e042ae-4d91-471c-8836-52f749fed689.c000.snappy.parquet
```
### Athena depois do backfill
```
madrugada 7d: 11137
count(*), count(DISTINCT corrida_id): 518400 518400
dt=2026-11-01: 17280 corridas, 1591 na madrugada
```
## Execuções do job (aws glue get-job-runs): início, estado, segundos, DPU-segundos, --DIAS
```
2026-11-04T09:26:44.506000-03:00	SUCCEEDED	100	200.0	2026-11-01
2026-11-04T09:23:28-03:00	SUCCEEDED	109	218.0	None
2026-11-04T09:17:19.418000-03:00	SUCCEEDED	164	328.0	None
2026-11-04T09:12:15.587000-03:00	SUCCEEDED	130	260.0	None
```

## terraform destroy (plano -destroy revisado e aplicado)
```
aws_iam_role_policy.bucket: Destruction complete after 0s
aws_athena_workgroup.wg: Destruction complete after 0s
aws_iam_role_policy_attachment.glue: Destruction complete after 0s
aws_glue_job.pipeline: Destruction complete after 0s
aws_glue_catalog_table.corridas: Destruction complete after 0s
aws_glue_catalog_table.raw: Destruction complete after 0s
aws_glue_catalog_database.lake: Destruction complete after 1s
aws_iam_role.job: Destruction complete after 1s
aws_s3_object.script: Destruction complete after 5s
aws_s3_bucket.lake: Destruction complete after 2s
Apply complete! Resources: 0 added, 0 changed, 10 destroyed.
```
## ./verificacao/verifica.sh --pos-destroy
```
PASSA  [5]  (10%)  destroy limpo: nenhum recurso eda-a25-grupo02 sobrou
terraform state list: 0 recursos
backend eda-tfstate-grupo02 intacto; chave nova aula-25/grupo02/terraform.tfstate (798 B, vazio de recursos)
```
