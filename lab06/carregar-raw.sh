#!/usr/bin/env bash
# Uso: ./carregar-raw.sh            (da raiz do pacote, depois do terraform apply)
# Gera os 30 dias e planta os dois problemas do Exercício 05 (o pipeline do Ciclo 6 tem de
# continuar certo): a madrugada de 3 dias atrás chega hoje, e o arquivo de 5 dias atrás chega duas vezes.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
cd "$(dirname "$0")"
BUCKET="$(terraform -chdir=terraform output -raw bucket)"
SAIDA=/tmp/eda-a29
rm -rf "$SAIDA"
python3 app/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida "$SAIDA" >/dev/null
python3 app/plantar-problemas.py --saida "$SAIDA" --atraso 3 --reentrega 5
echo ">> sincronizando com s3://$BUCKET/raw/"
aws s3 rm "s3://$BUCKET/raw/" --recursive --only-show-errors
aws s3 sync "$SAIDA/raw/" "s3://$BUCKET/raw/" --only-show-errors
aws s3 ls "s3://$BUCKET/raw/corridas/" --recursive --summarize | tail -2
HOJE=$(ls "$SAIDA/raw/corridas" | sed -n 's#^dt=##p' | sort | tail -1)
echo "hoje=$HOJE  desde=$(python3 -c "import datetime as d; print(d.date.fromisoformat('$HOJE') - d.timedelta(days=6))")"
