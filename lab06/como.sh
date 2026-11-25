#!/usr/bin/env bash
# Uso: ./como.sh <prefeitura|analista> "<SQL>"
# Roda a consulta no workgroup do grupo COMO o perfil (assume o papel por 15 min) e imprime o
# resultado e o Data scanned; se o Athena recusar, imprime RECUSADO e o motivo.
#   ./como.sh prefeitura "SELECT sum(corridas) FROM eda_a29_<sufixo>_refined.madrugada_bairro"
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
cd "$(dirname "$0")"
PERFIL="${1:?uso: ./como.sh <prefeitura|analista> \"<SQL>\"}"; SQL="${2:?falta o SQL}"
ARN="$(terraform -chdir=terraform output -raw "papel_$PERFIL" 2>/dev/null)" || { echo "perfil desconhecido: $PERFIL" >&2; exit 2; }
WG="$(terraform -chdir=terraform output -raw workgroup)"
read -r AK SK ST < <(aws sts assume-role --role-arn "$ARN" --role-session-name "eda-a29-$PERFIL" \
  --duration-seconds 900 --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text) || exit 1
export AWS_ACCESS_KEY_ID="$AK" AWS_SECRET_ACCESS_KEY="$SK" AWS_SESSION_TOKEN="$ST"; unset AWS_PROFILE
ID=$(aws athena start-query-execution --work-group "$WG" --query-string "$SQL" \
     --query QueryExecutionId --output text) || { echo "RECUSADO antes de começar"; exit 1; }
while :; do
  read -r ESTADO BYTES < <(aws athena get-query-execution --query-execution-id "$ID" \
    --query 'QueryExecution.[Status.State,Statistics.DataScannedInBytes]' --output text)
  case "$ESTADO" in SUCCEEDED) break;; FAILED|CANCELLED)
    echo "RECUSADO: $(aws athena get-query-execution --query-execution-id "$ID" \
      --query 'QueryExecution.Status.StateChangeReason' --output text)"; exit 1;; esac
  sleep 1
done
aws athena get-query-results --query-execution-id "$ID" --output json | python3 -c '
import json, sys
for r in json.load(sys.stdin)["ResultSet"]["Rows"][:30]:
    print("\t".join(c.get("VarCharValue", "") for c in r["Data"]))'
echo "Data scanned: ${BYTES} bytes"
