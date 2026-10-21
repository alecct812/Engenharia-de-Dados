#!/usr/bin/env bash
# Uso: ./carregar-raw.sh            (rode da raiz do pacote, depois do terraform apply)
# Gera os mesmos 30 dias de corridas dos Labs 04 e 05 (seed 42) e copia para a raw
# do SEU bucket. O nome do bucket vem do output do Terraform: nada a digitar.
set -euo pipefail
cd "$(dirname "$0")"
REGION=us-east-1
BUCKET="$(terraform -chdir=terraform output -raw bucket_name)"
SAIDA=/tmp/eda-a21

echo ">> [1/2] gerando 30 dias de corridas em $SAIDA (seed 42, ~10 s)"
rm -rf "$SAIDA"
python3 app/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida "$SAIDA" | sed -n '1,6p'

echo ">> [2/2] copiando para s3://$BUCKET/raw/ (~112 MB; depende da rede)"
aws s3 rm "s3://$BUCKET/raw/" --recursive --region "$REGION" --only-show-errors
aws s3 sync "$SAIDA/raw/" "s3://$BUCKET/raw/" --region "$REGION" --only-show-errors
aws s3 ls "s3://$BUCKET/raw/corridas/" --recursive --summarize --region "$REGION" | tail -2
echo "esperado: Total Objects: 30 · Total Size: 117655606"
