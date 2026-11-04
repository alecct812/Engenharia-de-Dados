#!/usr/bin/env bash
# Uso: ./rodar-job.sh               roda o job com as decisões do terraform.tfvars
#      ./rodar-job.sh DIAS=AAAA-MM-DD   backfill de um dia (o resto continua como declarado)
# Espera até o fim e imprime o relatório que o job gravou.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
cd "$(dirname "$0")"
JOB="$(terraform -chdir=terraform output -raw job)"
BUCKET="$(terraform -chdir=terraform output -raw bucket)"
ARGS="{}"
if [[ $# -gt 0 ]]; then
  [[ "$1" == DIAS=* ]] || { echo "só DIAS=AAAA-MM-DD pode ser trocado aqui; o resto é decisão no Terraform" >&2; exit 2; }
  ARGS="{\"--DIAS\":\"${1#DIAS=}\"}"
fi
echo ">> disparando $JOB com $ARGS"
RUN_ID=$(aws glue start-job-run --job-name "$JOB" --arguments "$ARGS" --query JobRunId --output text)
while true; do
  ESTADO=$(aws glue get-job-run --job-name "$JOB" --run-id "$RUN_ID" --query JobRun.JobRunState --output text)
  echo "$(date +%H:%M:%S)  $ESTADO"
  case "$ESTADO" in SUCCEEDED) break;; FAILED|STOPPED|TIMEOUT|ERROR)
    aws glue get-job-run --job-name "$JOB" --run-id "$RUN_ID" --query JobRun.ErrorMessage --output text >&2; exit 1;; esac
  sleep 20
done
aws s3 cp "s3://$BUCKET/relatorios/corridas.json" -
