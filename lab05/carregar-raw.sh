#!/usr/bin/env bash
# Uso: ./carregar-raw.sh            (da raiz do pacote, depois do terraform apply)
# Gera os 30 dias do Lab 06, planta os DOIS problemas do exercício e carrega na raw:
#   --atraso 3     a madrugada de 3 dias atrás chega só hoje (o mesmo do Lab 06)
#   --reentrega 5  o arquivo de 5 dias atrás chega de novo no dia seguinte (o requisito novo)
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
cd "$(dirname "$0")"
BUCKET="$(terraform -chdir=terraform output -raw bucket)"
SAIDA=/tmp/eda-a25
rm -rf "$SAIDA"
python3 app/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida "$SAIDA" >/dev/null
python3 app/plantar-problemas.py --saida "$SAIDA" --atraso 3 --reentrega 5
echo ">> sincronizando com s3://$BUCKET/raw/"
aws s3 rm "s3://$BUCKET/raw/" --recursive --only-show-errors
aws s3 sync "$SAIDA/raw/" "s3://$BUCKET/raw/" --only-show-errors
aws s3 ls "s3://$BUCKET/raw/corridas/" --recursive --summarize | tail -2
