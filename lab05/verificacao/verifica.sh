#!/usr/bin/env bash
# verifica.sh — Exercício 05 (Aula 25). Rode da raiz do pacote, na conta do grupo:
#   ./verificacao/verifica.sh                 critérios 0 a 4 (roda o job UMA vez a mais: ~3 min)
#   ./verificacao/verifica.sh --pos-destroy   critério 5, depois do terraform destroy
# Imprime PASSA/FALHA por critério e uma linha de evidência para colar no PR.
set -uo pipefail
cd "$(dirname "$0")/.."
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
CERTA=11137; TOTAL=518400
pontos=0
passa() { printf "PASSA  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; pontos=$((pontos + $2)); }
falha() { printf "FALHA  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }

SUFIXO="$(sed -n 's/^ *sufixo *= *"\(.*\)".*/\1/p' terraform/terraform.tfvars 2>/dev/null | head -1)"
[[ -n "$SUFIXO" ]] || { echo "não achei o sufixo em terraform/terraform.tfvars"; exit 2; }

# ------------------------------------------------------------- critério 5 (pós-destroy)
if [[ "${1:-}" == "--pos-destroy" ]]; then
  sobra=""
  aws s3api head-bucket --bucket "eda-a25-lake-$SUFIXO" >/dev/null 2>&1 && sobra="$sobra bucket"
  aws glue get-database --name "eda_a25_$SUFIXO" >/dev/null 2>&1 && sobra="$sobra database"
  aws glue get-job --job-name "eda-a25-$SUFIXO-pipeline" >/dev/null 2>&1 && sobra="$sobra job"
  aws athena get-work-group --work-group "eda-a25-$SUFIXO-wg" >/dev/null 2>&1 && sobra="$sobra workgroup"
  aws iam get-role --role-name "eda-a25-$SUFIXO-glue" >/dev/null 2>&1 && sobra="$sobra papel"
  if [[ -z "$sobra" ]]; then passa 5 10 "destroy limpo: nenhum recurso eda-a25-$SUFIXO sobrou"
  else falha 5 10 "sobraram:$sobra"; exit 1; fi
  exit 0
fi

out() { terraform -chdir=terraform output -raw "$1" 2>/dev/null; }
BUCKET="$(out bucket)"; DB="$(out database)"; WG="$(out workgroup)"
[[ -n "$BUCKET" && -n "$DB" && -n "$WG" ]] || { echo "sem outputs: rode terraform apply antes"; exit 2; }

athena() {   # imprime a primeira linha de resultado, colunas separadas por tab
  local id st
  id=$(aws athena start-query-execution --work-group "$WG" --query-execution-context "Database=$DB" \
       --query-string "$1" --query QueryExecutionId --output text) || return 1
  while :; do
    st=$(aws athena get-query-execution --query-execution-id "$id" --query QueryExecution.Status.State --output text)
    case "$st" in SUCCEEDED) break;; FAILED|CANCELLED) echo "ERRO"; return 1;; esac
    sleep 2
  done
  aws athena get-query-results --query-execution-id "$id" --query 'ResultSet.Rows[1].Data[*].VarCharValue' --output text
}

HOJE=$(aws s3 ls "s3://$BUCKET/raw/corridas/" | awk '{print $2}' | sed -n 's#^dt=\(.*\)/$#\1#p' | sort | tail -1)
[[ -n "$HOJE" ]] || { echo "raw vazia: rode ./carregar-raw.sh"; exit 2; }
DESDE=$(python3 -c "import datetime as d; print(d.date.fromisoformat('$HOJE') - d.timedelta(days=6))")
Q_MADR="SELECT count(*) FROM corridas WHERE dt >= '$DESDE' AND faixa_hora BETWEEN 0 AND 5"
Q_TAB="SELECT count(*), count(DISTINCT corrida_id) FROM corridas"

# ------------------------------------------------------------- critério 0 (elimina)
tipo=$(python3 -c "import json;print(json.load(open('terraform/.terraform/terraform.tfstate'))['backend']['type'])" 2>/dev/null)
classe=$(aws glue get-table --database-name "$DB" --name corridas --query 'Table.Parameters.classification' --output text 2>/dev/null)
if [[ "$tipo" == "s3" && "$classe" == "parquet" ]]; then
  echo "OK     [0]  (elimina)  backend remoto s3 e trusted em Parquet"
else
  echo "FALHA  [0]  (elimina)  backend=${tipo:-local} classificação=${classe:-?}: nada mais conta"; exit 1
fi

# ------------------------------------------------------------- critério 1
m1=$(athena "$Q_MADR"); read -r n1 d1 <<<"$(athena "$Q_TAB")"
if [[ "$m1" == "$CERTA" ]]; then passa 1 20 "a madrugada de 7 dias tem $m1 corridas, incluindo as atrasadas"
else falha 1 20 "a madrugada de 7 dias tem ${m1} corridas; a resposta certa é $CERTA"; fi

# ------------------------------------------------------------- critério 2: roda o job mais uma vez
echo "       rodando o job mais uma vez (~3 min) para o critério 2…"
if ./rodar-job.sh >/tmp/eda-a25-verifica-run.log 2>&1; then
  m2=$(athena "$Q_MADR"); read -r n2 d2 <<<"$(athena "$Q_TAB")"
  if [[ "$m1" == "$m2" && "$n1" == "$n2" ]]; then passa 2 25 "rodar de novo não mudou nada: $n1 linhas e $m1 na madrugada, antes e depois"
  else falha 2 25 "antes $n1 linhas / $m1 na madrugada; depois $n2 / $m2"; fi
else
  n2=$n1; d2=$d1; falha 2 25 "o job falhou na segunda execução (veja /tmp/eda-a25-verifica-run.log)"
fi

# ------------------------------------------------------------- critério 3
if [[ "$n2" == "$d2" && "$n2" == "$TOTAL" ]]; then passa 3 15 "uma linha por corrida: $n2 linhas, $d2 corridas distintas"
else falha 3 15 "$n2 linhas para $d2 corridas distintas (o certo: $TOTAL e $TOTAL)"; fi

# ------------------------------------------------------------- critério 4
terraform -chdir=terraform plan -detailed-exitcode -input=false -lock=false >/dev/null 2>&1; rc=$?
if [[ $rc -eq 0 ]]; then passa 4 10 "terraform plan limpo: o segundo apply não mudaria nada"
else falha 4 10 "terraform plan com mudanças pendentes (código $rc)"; fi

echo
echo "Critérios automáticos: $pontos / 70 pontos-percentuais"
echo "Falta o que o script não mede: o critério 5 (rode com --pos-destroy depois do destroy) e o DECISOES.md (20%)."
echo
echo "evidência: sufixo=$SUFIXO hoje=$HOJE madrugada_7d=$m1->${m2:-?} linhas=$n1->$n2 distintas=$d2 $(terraform -chdir=terraform output -json decisoes 2>/dev/null | tr -d ' \n')"
