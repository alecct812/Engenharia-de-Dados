#!/usr/bin/env bash
# Uso: ./rodar-job.sh               (rode da raiz do pacote, depois do carregar-raw.sh)
# Dispara o job Glue que grava a trusted em Parquet, espera terminar, mostra o
# relatorio e, SE a tabela nao usa partition projection, registra as particoes
# com MSCK REPAIR TABLE (DECISAO 05).
set -euo pipefail
cd "$(dirname "$0")"
REGION=us-east-1
out() { terraform -chdir=terraform output -raw "$1"; }
BUCKET="$(out bucket_name)"; JOB="$(out job_name)"; DB="$(out database_name)"
TABELA="$(out trusted_table_name)"; WG="$(out workgroup_name)"

echo ">> [1/3] disparando o job $JOB"
RUN_ID="$(aws glue start-job-run --job-name "$JOB" --region "$REGION" --query JobRunId --output text)"
while true; do
  ESTADO="$(aws glue get-job-run --job-name "$JOB" --run-id "$RUN_ID" --region "$REGION" \
            --query JobRun.JobRunState --output text)"
  echo "$(date +%H:%M:%S)  $ESTADO"
  case "$ESTADO" in
    SUCCEEDED) break ;;
    FAILED|STOPPED|TIMEOUT|ERROR)
      aws glue get-job-run --job-name "$JOB" --run-id "$RUN_ID" --region "$REGION" \
        --query JobRun.ErrorMessage --output text; exit 1 ;;
  esac
  sleep 20
done

echo ">> [2/3] o relatorio que o job gravou"
aws s3 cp "s3://$BUCKET/relatorios/trusted-parquet.json" - --region "$REGION"

echo ">> [3/3] registro das particoes"
PROJ="$(aws glue get-table --database-name "$DB" --name "$TABELA" --region "$REGION" \
        --query 'Table.Parameters."projection.enabled"' --output text)"
if [ "$PROJ" = "true" ]; then
  echo "partition projection ligada: o Athena calcula as pastas, nada a registrar."
else
  QID="$(aws athena start-query-execution --work-group "$WG" --region "$REGION" \
         --query-string "MSCK REPAIR TABLE $DB.$TABELA" --query QueryExecutionId --output text)"
  while true; do
    E="$(aws athena get-query-execution --query-execution-id "$QID" --region "$REGION" \
         --query QueryExecution.Status.State --output text)"
    case "$E" in SUCCEEDED) echo "MSCK REPAIR TABLE: ok"; break ;;
      FAILED|CANCELLED) echo "MSCK falhou: $E"; exit 1 ;; esac
    sleep 3
  done
fi
