#!/usr/bin/env bash
# Uso: ./rodar-jobs.sh              raw -> trusted e, em seguida, trusted -> refined
#      ./rodar-jobs.sh refined      só trusted -> refined
# Espera cada job terminar e imprime o relatório que ele gravou.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
cd "$(dirname "$0")"
BUCKET="$(terraform -chdir=terraform output -raw bucket)"
roda() {   # $1 = output do job, $2 = relatório
  local job run estado
  job="$(terraform -chdir=terraform output -raw "$1")"
  echo ">> disparando $job"
  run=$(aws glue start-job-run --job-name "$job" --query JobRunId --output text)
  while true; do
    estado=$(aws glue get-job-run --job-name "$job" --run-id "$run" --query JobRun.JobRunState --output text)
    echo "$(date +%H:%M:%S)  $estado"
    case "$estado" in SUCCEEDED) break;; FAILED|STOPPED|TIMEOUT|ERROR)
      aws glue get-job-run --job-name "$job" --run-id "$run" --query JobRun.ErrorMessage --output text >&2; exit 1;; esac
    sleep 20
  done
  aws s3 cp "s3://$BUCKET/relatorios/$2.json" -
}
[[ "${1:-}" == refined ]] || roda job_trusted corridas
roda job_refined madrugada_bairro
