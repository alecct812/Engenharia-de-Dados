# EVIDENCIA.md · Exercício 06: o lake em camadas, e quem lê cada uma

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1` · executado em 2026-11-25

A execução na ordem em que foi feita, com a saída dos comandos. O estado ficou no backend remoto
(`eda-tfstate-grupo02`, trava `eda-tflock`), com a chave `aula-29/grupo02/terraform.tfstate`. Cada
apply e o destroy foram feitos a partir de um `terraform plan -out` revisado antes. O número da
conta foi trocado por `<conta>`.

Ordem: apply (com a recusa do `wildcard`), correção e segundo apply, carga da raw, os dois jobs,
correção da política `consumo`, consultas como cada perfil, medição da DECISÃO 01, permissões no
Lake Formation, `verifica.sh`, destroy e `verifica.sh --pos-destroy`.

## Adaptações à conta compartilhada
A conta do g02 é compartilhada pela turma: nela estão os usuários `eda-grupo01` a `eda-grupo11`,
os databases de outros grupos e o Lab 07 do professor. No início, os administradores do Lake
Formation eram `gportela` e `eda-grupo09`. Por isso o `main.tf` difere do pacote em cinco pontos.
Perguntado em 2026-11-25, o professor aprovou desligar o acesso automático só nos nossos databases,
em vez de mexer na configuração da conta.

1. **Sem `aws_lakeformation_data_lake_settings`.** Esse recurso gravaria a lista de administradores
   da conta inteira só com o g02, desligaria o acesso automático para os databases de todos os
   grupos, e o destroy resetaria as duas coisas. Em vez dele, cada um dos nossos 3 databases tem
   `create_table_default_permission` vazio, e nenhuma das nossas tabelas nasce com
   `IAM_ALLOWED_PRINCIPALS` (ver "O que o Lake Formation diz"). Não alteramos os administradores
   da conta. Durante a execução, outro grupo acrescentou `eda-grupo04`, e depois do destroy a
   lista seguia com os mesmos três. São 31 recursos em vez de 32.
2. **O registro das pastas vem depois das tabelas** (`depends_on`). Sem sermos administradores,
   criar uma tabela numa pasta já registrada exigiria `DATA_LOCATION_ACCESS`.
3. **A analista recebe a refined pelo nome da tabela, e não por `wildcard`.** A concessão em todas
   as tabelas foi recusada (ver o 1º apply). Quem cria a tabela pode concedê-la pelo nome. Pelo
   mesmo motivo, a opção `banco` da DECISÃO 01 não funcionaria nesta conta.
4. **Correção na política `consumo`.** `s3:GetBucketLocation` estava sob a condição `s3:prefix`,
   que essa chamada não envia, e todas as consultas dos dois perfis falhavam. Ele passou para uma
   declaração própria. O `ListBucket` continua restrito a `athena-results/`, e o S3 direto nas
   camadas continuou negado (critério 2).

5. **`ignore_changes = [permissions]` nas 3 concessões `DESCRIBE` de database (`ver_banco`).** O
   padrão da conta põe `IAM_ALLOWED_PRINCIPALS ALL` nos databases novos, e o provider lê esse `ALL`
   junto com o `DESCRIBE` do perfil. Sem essa linha, todo `plan` depois do apply propunha recriar as
   3 concessões (ver o 2º apply). O `ALL` não dá acesso a dado nenhum, porque ler uma tabela exige
   permissão na tabela, e o critério 2 passou. Como as concessões são sempre só `DESCRIBE`, não há
   mudança real a perder. Esta linha entrou depois da execução principal e foi confirmada num ciclo
   próprio (ver "Confirmação do plan limpo", no fim).

## terraform apply (1º): 31 recursos planejados
```
aws_glue_catalog_database.camada["refined"]: Creation complete after 1s [id=<conta>:eda_a29_grupo02_refined]
aws_glue_catalog_database.camada["raw"]: Creation complete after 1s [id=<conta>:eda_a29_grupo02_raw]
aws_glue_catalog_database.camada["trusted"]: Creation complete after 1s [id=<conta>:eda_a29_grupo02_trusted]
aws_iam_role.perfil["prefeitura"]: Creation complete after 1s [id=eda-a29-grupo02-prefeitura]
aws_iam_role.job: Creation complete after 1s [id=eda-a29-grupo02-glue]
aws_iam_role.lf: Creation complete after 1s [id=eda-a29-grupo02-lf]
aws_iam_role.perfil["analista"]: Creation complete after 1s [id=eda-a29-grupo02-analista]
aws_iam_role_policy_attachment.glue: Creation complete after 1s [id=eda-a29-grupo02-glue-20261125121342594900000001]
aws_glue_catalog_table.refined: Creation complete after 1s [id=<conta>:eda_a29_grupo02_refined:madrugada_bairro]
aws_glue_catalog_table.raw: Creation complete after 1s [id=<conta>:eda_a29_grupo02_raw:corridas]
aws_glue_catalog_table.trusted: Creation complete after 1s [id=<conta>:eda_a29_grupo02_trusted:corridas]
aws_s3_bucket.lake: Creation complete after 4s [id=eda-a29-lake-grupo02]
aws_iam_role_policy.bucket: Creation complete after 0s [id=eda-a29-grupo02-glue:bucket-rw]
aws_s3_object.script["pipeline-corridas.py"]: Creation complete after 0s [id=scripts/pipeline-corridas.py]
aws_s3_object.script["refinar-madrugada.py"]: Creation complete after 0s [id=scripts/refinar-madrugada.py]
aws_iam_role_policy.lf: Creation complete after 1s [id=eda-a29-grupo02-lf:camadas-rw]
aws_glue_job.refined: Creation complete after 1s [id=eda-a29-grupo02-refined]
aws_glue_job.trusted: Creation complete after 1s [id=eda-a29-grupo02-trusted]
aws_athena_workgroup.wg: Creation complete after 1s [id=eda-a29-grupo02-wg]
aws_lakeformation_resource.camada["raw"]: Creation complete after 0s [id=arn:aws:s3:::eda-a29-lake-grupo02/raw]
aws_lakeformation_resource.camada["refined"]: Creation complete after 0s [id=arn:aws:s3:::eda-a29-lake-grupo02/refined]
aws_lakeformation_resource.camada["trusted"]: Creation complete after 1s [id=arn:aws:s3:::eda-a29-lake-grupo02/trusted]
aws_iam_policy.consumo: Creation complete after 1s [id=arn:aws:iam::<conta>:policy/eda-a29-grupo02-consumo]
aws_iam_role_policy_attachment.perfil["analista"]: Creation complete after 0s [id=eda-a29-grupo02-analista-20261125121346856400000002]
aws_iam_role_policy_attachment.perfil["prefeitura"]: Creation complete after 0s [id=eda-a29-grupo02-prefeitura-20261125121346865000000003]
aws_lakeformation_permissions.ver_banco["analista-refined"]: Creation complete after 10s [id=835363208]
aws_lakeformation_permissions.ver_banco["analista-trusted"]: Creation complete after 10s [id=525979632]
aws_lakeformation_permissions.ver_banco["prefeitura-refined"]: Creation complete after 10s [id=2066001635]
aws_lakeformation_permissions.prefeitura_refined: Creation complete after 10s [id=951051600]
aws_lakeformation_permissions.analista_trusted: Creation complete after 10s [id=1696271679]
│ Error: creating Lake Formation Permissions (... [DESCRIBE SELECT] ...): GrantPermissions, StatusCode: 400,
│ api error AccessDeniedException: Resource does not exist or requester is not authorized to access requested permissions.
│   with aws_lakeformation_permissions.analista_refined   (table { wildcard = true })
```
A única concessão recusada foi a de todas as tabelas (`wildcard`), que exige um administrador do
Lake Formation. Ela passou a ser feita pelo nome da tabela ("Adaptações", item 3).

## terraform apply (2º)
```
aws_lakeformation_permissions.ver_banco["analista-refined"]: Destruction complete after 1s
aws_lakeformation_permissions.ver_banco["prefeitura-refined"]: Destruction complete after 1s
aws_lakeformation_permissions.ver_banco["analista-trusted"]: Destruction complete after 1s
aws_lakeformation_permissions.analista_refined: Creation complete after 1s [id=4047610256]
aws_lakeformation_permissions.ver_banco["analista-refined"]: Creation complete after 0s [id=835363208]
aws_lakeformation_permissions.ver_banco["prefeitura-refined"]: Creation complete after 0s [id=2066001635]
aws_lakeformation_permissions.ver_banco["analista-trusted"]: Creation complete after 0s [id=525979632]
Apply complete! Resources: 4 added, 0 changed, 3 destroyed.
```
As 3 concessões `ver_banco` foram recriadas por causa da deriva descrita em "Adaptações".

## ./carregar-raw.sh
```

hoje (última pasta) .... dt=2026-11-25
dado atrasado .......... 1.591 corridas da madrugada de 2026-11-22
                         saíram de dt=2026-11-22/ e chegaram em dt=2026-11-25/parte-0002-atrasadas.json
reentrega .............. 17.280 corridas de 2026-11-20 chegaram de novo em dt=2026-11-21/parte-0002-reenvio.json

as linhas para o Athena, prontas para copiar:
    WHERE dt >= '2026-11-19'          -- os últimos 7 dias
    WHERE dt = '2026-11-22'      -- o dia da madrugada atrasada

>> sincronizando com s3://eda-a29-lake-grupo02/raw/
Total Objects: 32
   Total Size: 121612198
hoje=2026-11-25  desde=2026-11-19
```

## ./rodar-jobs.sh (trusted e depois refined)
```
>> disparando eda-a29-grupo02-trusted
09:19:44  SUCCEEDED
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
}>> disparando eda-a29-grupo02-refined
09:21:03  SUCCEEDED
{
  "tabela": "madrugada_bairro",
  "dias": "todos",
  "corridas_lidas_da_trusted": 518400,
  "corridas_da_madrugada": 47730,
  "linhas_gravadas_neste_run": 660,
  "dias_gravados_neste_run": 30,
  "linhas_na_tabela": 660,
  "bairros_na_tabela": 22,
  "corridas_somadas_na_tabela": 47730
}saida=0

```

## Correção da política `consumo` (GetBucketLocation fora da condição s3:prefix)
Antes, toda consulta dos dois perfis parava em:
```
aws: [ERROR]: An error occurred (InvalidRequestException) when calling the StartQueryExecution operation:
Unable to verify/create output bucket eda-a29-lake-grupo02
AthenaErrorCode: INSUFFICIENT_PERMISSIONS
```
Depois de `terraform apply` só da política (`aws_iam_policy.consumo: Modifications complete`;
`Resources: 0 added, 1 changed, 0 destroyed`), as consultas abaixo.

## Como cada perfil (./como.sh)
```
$ ./como.sh prefeitura "SELECT sum(corridas) FROM eda_a29_grupo02_refined.madrugada_bairro WHERE dt >= '2026-11-19'"
_col0
11137
Data scanned: 998 bytes

$ ./como.sh prefeitura "SELECT count(*) FROM eda_a29_grupo02_trusted.corridas WHERE dt = '2026-11-25'"
RECUSADO: TABLE_NOT_FOUND: line 1:22: Table 'awsdatacatalog.eda_a29_grupo02_trusted.corridas' does not exist

$ ./como.sh prefeitura "SELECT count(*) FROM eda_a29_grupo02_raw.corridas WHERE dt = '2026-11-25'"
RECUSADO: TABLE_NOT_FOUND: line 1:22: Table 'awsdatacatalog.eda_a29_grupo02_raw.corridas' does not exist

$ ./como.sh analista "SELECT count(bairro) FROM eda_a29_grupo02_trusted.corridas"
_col0
518400
Data scanned: 334757 bytes

$ ./como.sh analista "SELECT passageiro_id FROM eda_a29_grupo02_trusted.corridas WHERE dt = '2026-11-25' LIMIT 1"
RECUSADO: COLUMN_NOT_FOUND: Column 'passageiro_id' cannot be resolved or requester is not authorized to access requested resources

$ ./como.sh analista "SELECT motorista_id FROM eda_a29_grupo02_trusted.corridas WHERE dt = '2026-11-25' LIMIT 1"
RECUSADO: COLUMN_NOT_FOUND: Column 'motorista_id' cannot be resolved or requester is not authorized to access requested resources

$ ./como.sh analista "SELECT * FROM eda_a29_grupo02_trusted.corridas WHERE dt = '2026-11-25' LIMIT 1"
corrida_id	bairro	inicio	fim	distancia_km	duracao_min	valor	faixa_hora	chegada	dt
c-00501121	Bongi	2026-11-25 00:47:19.000	2026-11-25 00:53:13.000	2.86	5.9	14.4	0	2026-11-25	2026-11-25
Data scanned: 460880 bytes

$ ./como.sh analista "SELECT count(*), count(DISTINCT corrida_id) FROM eda_a29_grupo02_trusted.corridas"
_col0	_col1
518400	518400
Data scanned: 2559892 bytes

$ ./como.sh analista "SELECT sum(corridas) FROM eda_a29_grupo02_refined.madrugada_bairro WHERE dt >= '2026-11-19'"
_col0
11137
Data scanned: 998 bytes

$ ./como.sh analista "SELECT count(*) FROM eda_a29_grupo02_raw.corridas WHERE dt = '2026-11-25'"
RECUSADO: TABLE_NOT_FOUND: line 1:22: Table 'awsdatacatalog.eda_a29_grupo02_raw.corridas' does not exist

```

## DECISÃO 01 medida: uma tabela nova na refined, criada fora do Terraform e apagada em seguida
```
$ aws glue create-table (fora do Terraform) eda_a29_grupo02_refined.teste_com_motorista  -- motorista_id, por engano
criada
$ aws glue get-tables (como engenharia) na refined
madrugada_bairro	teste_com_motorista

$ ./como.sh prefeitura "SELECT count(*) FROM eda_a29_grupo02_refined.teste_com_motorista"
RECUSADO: TABLE_NOT_FOUND: line 1:22: Table 'awsdatacatalog.eda_a29_grupo02_refined.teste_com_motorista' does not exist

$ aws glue get-tables (como prefeitura) na refined
madrugada_bairro

$ aws s3 ls s3://eda-a29-lake-grupo02/refined/ (como prefeitura)

aws: [ERROR]: An error occurred (AccessDenied) when calling the ListObjectsV2 operation: User: arn:aws:sts::<conta>:assumed-role/eda-a29-grupo02-prefeitura/medir-prefeitura is not authorized to perform: s3:ListBucket on resource: "arn:aws:s3:::eda-a29-lake-grupo02" because no identity-based policy allows the s3:ListBucket action
$ aws s3 ls s3://eda-a29-lake-grupo02/trusted/corridas/ (como prefeitura)

aws: [ERROR]: An error occurred (AccessDenied) when calling the ListObjectsV2 operation: User: arn:aws:sts::<conta>:assumed-role/eda-a29-grupo02-prefeitura/medir-prefeitura is not authorized to perform: s3:ListBucket on resource: "arn:aws:s3:::eda-a29-lake-grupo02" because no identity-based policy allows the s3:ListBucket action
$ aws s3 cp s3://eda-a29-lake-grupo02/raw/corridas/dt=2026-11-25/parte-0001.json - (como prefeitura)
download failed: s3://eda-a29-lake-grupo02/raw/corridas/dt=2026-11-25/parte-0001.json to - An error occurred (403) when calling the HeadObject operation: Forbidden

$ aws glue delete-table teste_com_motorista
apagada
madrugada_bairro
```

## O que o Lake Formation diz (antes do destroy)
```
$ aws lakeformation get-data-lake-settings (admins da conta: não mexemos)
arn:aws:iam::<conta>:user/eda-grupo04	arn:aws:iam::<conta>:user/gportela	arn:aws:iam::<conta>:user/eda-grupo09
IAM_ALLOWED_PRINCIPALS

$ aws lakeformation list-permissions --resource Table eda_a29_grupo02_raw.corridas
arn:aws:iam::<conta>:user/eda-grupo02	ALL,ALTER,DELETE,DESCRIBE,DROP,INSERT
arn:aws:iam::<conta>:user/eda-grupo02	SELECT

$ aws lakeformation list-permissions --resource Table eda_a29_grupo02_trusted.corridas
arn:aws:iam::<conta>:role/eda-a29-grupo02-analista	SELECT
arn:aws:iam::<conta>:user/eda-grupo02	ALL,ALTER,DELETE,DESCRIBE,DROP,INSERT
arn:aws:iam::<conta>:user/eda-grupo02	SELECT

$ aws lakeformation list-permissions --resource Table eda_a29_grupo02_refined.madrugada_bairro
arn:aws:iam::<conta>:role/eda-a29-grupo02-prefeitura	DESCRIBE
arn:aws:iam::<conta>:role/eda-a29-grupo02-prefeitura	SELECT
arn:aws:iam::<conta>:role/eda-a29-grupo02-analista	DESCRIBE
arn:aws:iam::<conta>:role/eda-a29-grupo02-analista	SELECT
arn:aws:iam::<conta>:user/eda-grupo02	ALL,ALTER,DELETE,DESCRIBE,DROP,INSERT
arn:aws:iam::<conta>:user/eda-grupo02	SELECT

$ aws lakeformation list-resources (as pastas do grupo)
arn:aws:s3:::eda-a29-lake-grupo02/raw	arn:aws:iam::<conta>:role/eda-a29-grupo02-lf
arn:aws:s3:::eda-a29-lake-grupo02/refined	arn:aws:iam::<conta>:role/eda-a29-grupo02-lf
arn:aws:s3:::eda-a29-lake-grupo02/trusted	arn:aws:iam::<conta>:role/eda-a29-grupo02-lf
$ aws lakeformation list-permissions --principal <analista> --resource Table trusted.corridas (a permissão por coluna)
[
    {
        "perm": [
            "SELECT"
        ],
        "recurso": {
            "TableWithColumns": {
                "CatalogId": "<conta>",
                "DatabaseName": "eda_a29_grupo02_trusted",
                "Name": "corridas",
                "ColumnWildcard": {
                    "ExcludedColumnNames": [
                        "motorista_id",
                        "passageiro_id"
                    ]
                }
            }
        }
    }
]
```

## ./verificacao/verifica.sh
```
OK     [0]  (elimina)  backend remoto s3, três databases (um por camada) e a refined em Parquet
PASSA  [1]  (20%)  a Prefeitura lê a refined: 11137 corridas na madrugada dos últimos 7 dias
PASSA  [2]  (25%)  a Prefeitura não lê a trusted, nem a raw, nem o S3 direto
PASSA  [3]  (15%)  a analista lê a trusted (518400 corridas) e não vê passageiro_id
PASSA  [4]  (10%)  o contrato da refined está no catálogo: descrição (150 caracteres), dono 'Engenharia de Dados - grupo 02', comentário em toda coluna

Critérios automáticos: 70 / 70 pontos-percentuais
Falta o que o script não mede: o critério 5 (rode com --pos-destroy depois do destroy) e o DECISOES.md (20%).

evidência: sufixo=grupo02 hoje=2026-11-25 prefeitura_refined=11137 prefeitura_trusted=RECUSADO prefeitura_raw=RECUSADO prefeitura_s3=RECUSADO analista_trusted=518400 analista_passageiro=RECUSADO {"colunas_ocultas_analista":["motorista_id","passageiro_id"],"escopo_prefeitura":"tabela"}
```

## terraform destroy (plano -destroy revisado e aplicado)
```
aws_lakeformation_resource.camada["refined"]: Destruction complete after 0s
aws_lakeformation_resource.camada["trusted"]: Destruction complete after 0s
aws_lakeformation_permissions.ver_banco["prefeitura-refined"]: Destruction complete after 0s
aws_glue_job.refined: Destruction complete after 0s
aws_lakeformation_permissions.ver_banco["analista-trusted"]: Destruction complete after 1s
aws_iam_role_policy_attachment.perfil["prefeitura"]: Destruction complete after 1s
aws_iam_role_policy_attachment.glue: Destruction complete after 1s
aws_iam_role_policy_attachment.perfil["analista"]: Destruction complete after 1s
aws_lakeformation_permissions.ver_banco["analista-refined"]: Destruction complete after 1s
aws_lakeformation_permissions.analista_trusted: Destruction complete after 1s
aws_glue_job.trusted: Destruction complete after 1s
aws_lakeformation_permissions.analista_refined: Destruction complete after 1s
aws_iam_role_policy.bucket: Destruction complete after 1s
aws_lakeformation_resource.camada["raw"]: Destruction complete after 0s
aws_lakeformation_permissions.prefeitura_refined: Destruction complete after 1s
aws_iam_role_policy.lf: Destruction complete after 0s
aws_s3_object.script["refinar-madrugada.py"]: Destruction complete after 0s
aws_s3_object.script["pipeline-corridas.py"]: Destruction complete after 0s
aws_glue_catalog_table.raw: Destruction complete after 0s
aws_glue_catalog_table.trusted: Destruction complete after 0s
aws_glue_catalog_table.refined: Destruction complete after 0s
aws_iam_policy.consumo: Destruction complete after 0s
aws_iam_role.job: Destruction complete after 1s
aws_iam_role.perfil["analista"]: Destruction complete after 1s
aws_glue_catalog_database.camada["refined"]: Destruction complete after 1s
aws_glue_catalog_database.camada["trusted"]: Destruction complete after 1s
aws_iam_role.perfil["prefeitura"]: Destruction complete after 1s
aws_iam_role.lf: Destruction complete after 1s
aws_glue_catalog_database.camada["raw"]: Destruction complete after 1s
aws_athena_workgroup.wg: Destruction complete after 1s
aws_s3_bucket.lake: Destruction complete after 3s
Apply complete! Resources: 0 added, 0 changed, 31 destroyed.
```

## ./verificacao/verifica.sh --pos-destroy
```
PASSA  [5]  (10%)  destroy limpo: nenhum recurso eda-a29-grupo02 sobrou
terraform state list: 0 recursos
admins LF da conta: arn:aws:iam::<conta>:user/eda-grupo04	arn:aws:iam::<conta>:user/eda-grupo09	arn:aws:iam::<conta>:user/gportela
backend: 2026-11-25 09:37:47        814 terraform.tfstate
```

## Confirmação do plan limpo (ciclo com o `main.tf` final, sem rodar os jobs)
Depois da execução acima entrou o `ignore_changes` das concessões `ver_banco` (Adaptações, item 5).
Com o `main.tf` final, subimos a stack de novo, conferimos o `plan` e derrubamos:
```
$ terraform plan -out tfplan.bin
Plan: 31 to add, 0 to change, 0 to destroy.
$ terraform apply tfplan.bin
Apply complete! Resources: 31 added, 0 changed, 0 destroyed.
$ terraform plan -detailed-exitcode
No changes. Your infrastructure matches the configuration.
exit=0
$ terraform plan -destroy -out tfplan-destroy.bin && terraform apply tfplan-destroy.bin
Plan: 0 to add, 0 to change, 31 to destroy.
Apply complete! Resources: 0 added, 0 changed, 31 destroyed.
$ ./verificacao/verifica.sh --pos-destroy
PASSA  [5]  (10%)  destroy limpo: nenhum recurso eda-a29-grupo02 sobrou
terraform state list: 0 recursos
admins LF da conta: arn:aws:iam::<conta>:user/eda-grupo04	arn:aws:iam::<conta>:user/gportela	arn:aws:iam::<conta>:user/eda-grupo09
```
O apply único subiu os 31 recursos sem erro: a concessão por nome (item 3) e a política corrigida
(item 4) já estavam no `main.tf`.
