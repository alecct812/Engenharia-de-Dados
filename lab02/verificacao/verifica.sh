#!/usr/bin/env bash
# =============================================================================
# verifica.sh — Exercício 02 (Aula 08)
# Roda na SUA conta e imprime PASSA/FALHA por critério da rubrica.
# Rode ANTES de entregar: a nota não é surpresa.
#
# Uso:
#   ./verifica.sh                 # critérios 0 a 4 e 6 (stack no ar)
#   ./verifica.sh --pos-destroy   # critério 5 (rode depois do terraform destroy)
#
# Pré-requisitos: AWS CLI autenticada, Terraform aplicado (para ler os outputs),
# e a amostra de dados já enviada ao S3.
# =============================================================================
set -uo pipefail

TFDIR="${TFDIR:-../terraform}"
REGIAO="${AWS_REGION:-us-east-1}"
DECISOES="${DECISOES:-../DECISOES.md}"
HOJE="$(date +%F)"
POS_DESTROY=0
[ "${1:-}" = "--pos-destroy" ] && POS_DESTROY=1

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; OFF=$'\e[0m'
notas=0; total=0
linha(){ printf '%s\n' "----------------------------------------------------------------"; }
pass(){ notas=$((notas+$2)); total=$((total+$2)); printf "${GREEN}PASSA${OFF}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail(){ total=$((total+$2)); printf "${RED}FALHA${OFF}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
info(){ printf "${DIM}       %s${OFF}\n" "$1"; }

tfout(){ terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }

# ---------------------------------------------------------------- pós-destroy --
if [ "$POS_DESTROY" = "1" ]; then
  echo "${BOLD}Critério 5 — destroy limpo${OFF}"; linha
  SUF="$(terraform -chdir="$TFDIR" output -raw bucket_name 2>/dev/null | sed 's/^eda-a08-lake-//')"
  if [ -z "$SUF" ]; then
    # sem state: tenta pelo tfvars
    SUF="$(grep -E '^\s*sufixo' "$TFDIR/terraform.tfvars" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/')"
  fi
  orfaos="$(aws s3 ls --region "$REGIAO" 2>/dev/null | grep -E "eda-a08-(lake|results)-${SUF}\b" || true)"
  if [ -z "$orfaos" ]; then
    pass "5" 15 "nenhum bucket órfão."
  else
    fail "5" 15 "há bucket órfão:"; echo "$orfaos"
    info "esvazie e apague: aws s3 rb s3://NOME --force"
  fi
  linha; printf "${BOLD}Critério 5: %s/15%%${OFF}\n" "$notas"
  exit 0
fi

echo "${BOLD}Exercício 02 — verificação (região $REGIAO, hoje $HOJE)${OFF}"; linha

# ------------------------------------------------------- critério 0 (elimina) --
echo "${BOLD}Critério 0 — Terraform, schema declarado, sem Crawler (ELIMINATÓRIO)${OFF}"
if [ ! -f "$TFDIR/main.tf" ]; then
  fail "0" 0 "não achei $TFDIR/main.tf — este exercício é em Terraform."; exit 2
fi
if grep -rqE 'resource\s+"aws_glue_crawler"' "$TFDIR"; then
  fail "0" 0 "há um aws_glue_crawler — o schema tem que ser DECLARADO, não inferido."; exit 2
fi
if ! grep -rqE 'resource\s+"aws_glue_catalog_table"' "$TFDIR"; then
  fail "0" 0 "não há aws_glue_catalog_table."; exit 2
fi
if [ -f "$TFDIR/../infra/template.yaml" ] || ls "$TFDIR"/*.yaml >/dev/null 2>&1; then
  info "aviso: há YAML por perto; a entrega deve ser Terraform."
fi
printf "${GREEN}OK${OFF}     [0]  requisito atendido (não pontua; libera o resto)\n"; linha

# ------------------------------------------------------ critério 1 (contrato) --
echo "${BOLD}Critério 1 — os cinco outputs de contrato${OFF}"
faltou=""
for o in bucket_name database_name table_name workgroup_name teto_bytes; do
  v="$(tfout "$o")"
  if [ -z "$v" ]; then faltou="$faltou $o"; else info "$o = $v"; fi
done
if [ -z "$faltou" ]; then pass "1" 10 "os cinco outputs existem e estão preenchidos."
else fail "1" 10 "faltou:$faltou (rodou terraform apply?)"; fi
linha

BUCKET="$(tfout bucket_name)"; DB="$(tfout database_name)"
TABLE="$(tfout table_name)"; WG="$(tfout workgroup_name)"; TETO="$(tfout teto_bytes)"

# ------------------------------------------------------- critério 2 (schema) --
echo "${BOLD}Critério 2 — schema declarado (≥8 colunas) e partição dt${OFF}"
if [ -n "$DB" ] && [ -n "$TABLE" ]; then
  ncol="$(aws glue get-table --region "$REGIAO" --database-name "$DB" --name "$TABLE" \
          --query "length(Table.StorageDescriptor.Columns)" --output text 2>/dev/null)"
  pk="$(aws glue get-table --region "$REGIAO" --database-name "$DB" --name "$TABLE" \
          --query "Table.PartitionKeys[?Name=='dt'].Name | [0]" --output text 2>/dev/null)"
  info "colunas declaradas: ${ncol:-?} · chave de partição: ${pk:-nenhuma}"
  if [ "${ncol:-0}" -ge 8 ] 2>/dev/null && [ "$pk" = "dt" ]; then
    pass "2" 25 "schema com $ncol colunas e partição dt."
  else fail "2" 25 "precisa de ≥8 colunas e chave de partição dt."; fi
else fail "2" 25 "sem database/table (critério 1 falhou)."; fi
linha

# ---------------------------------------------------- critério 3 (partições) --
echo "${BOLD}Critério 3 — ≥3 partições, uma delas a de hoje${OFF}"
if [ -n "$DB" ] && [ -n "$TABLE" ]; then
  parts="$(aws glue get-partitions --region "$REGIAO" --database-name "$DB" --table-name "$TABLE" \
           --query "Partitions[].Values[0]" --output text 2>/dev/null)"
  npart="$(echo "$parts" | wc -w | tr -d ' ')"
  info "partições registradas: ${npart:-0} -> $parts"
  temhoje="nao"; echo "$parts" | grep -qw "$HOJE" && temhoje="sim"
  if [ "${npart:-0}" -ge 3 ] && [ "$temhoje" = "sim" ]; then
    pass "3" 15 "$npart partições, incluindo a de hoje ($HOJE)."
  else fail "3" 15 "precisa de ≥3 partições e a de hoje ($HOJE). tem_hoje=$temhoje"; fi
else fail "3" 15 "sem tabela."; fi
linha

# --------------------------------------------------------- critério 4 (teto) --
echo "${BOLD}Critério 4 — o teto mata a consulta larga e deixa passar a estreita${OFF}"
roda_query(){ # $1 = SQL ; ecoa "ESTADO|BYTES|MOTIVO"
  local qid estado bytes motivo
  qid="$(aws athena start-query-execution --region "$REGIAO" --work-group "$WG" \
        --query-execution-context Database="$DB" \
        --query-string "$1" --query "QueryExecutionId" --output text 2>/dev/null)"
  [ -z "$qid" ] && { echo "SEM_ID|0|nao iniciou"; return; }
  for _ in $(seq 1 30); do
    estado="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
             --query "QueryExecution.Status.State" --output text 2>/dev/null)"
    case "$estado" in SUCCEEDED|FAILED|CANCELLED) break;; esac
    sleep 2
  done
  bytes="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
          --query "QueryExecution.Statistics.DataScannedInBytes" --output text 2>/dev/null)"
  motivo="$(aws athena get-query-execution --region "$REGIAO" --query-execution-id "$qid" \
          --query "QueryExecution.Status.StateChangeReason" --output text 2>/dev/null)"
  echo "${estado}|${bytes:-0}|${motivo:-}"
}
if [ -n "$WG" ] && [ -n "$DB" ]; then
  info "teto declarado: $TETO bytes"
  L="$(roda_query "SELECT count(*) FROM ${TABLE}")"                       # larga: todas as partições
  E="$(roda_query "SELECT count(*) FROM ${TABLE} WHERE dt='${HOJE}'")"    # estreita: só hoje
  lest="${L%%|*}"; lmot="${L##*|}"
  eest="${E%%|*}"; ebytes="$(echo "$E" | cut -d'|' -f2)"
  info "larga:    estado=$lest  motivo=${lmot:0:60}"
  info "estreita: estado=$eest  bytes=$ebytes"
  larga_morreu="nao"; echo "$lmot" | grep -qiE "bytes|cutoff|exceed" && larga_morreu="sim"
  [ "$lest" = "FAILED" ] && [ "$larga_morreu" = "sim" ] && larga_ok=1 || larga_ok=0
  [ "$eest" = "SUCCEEDED" ] && estreita_ok=1 || estreita_ok=0
  if [ "$larga_ok" = 1 ] && [ "$estreita_ok" = 1 ]; then
    pass "4" 15 "a larga foi barrada pelo teto e a estreita passou."
  else
    fail "4" 15 "larga_barrada=$larga_ok estreita_passou=$estreita_ok"
    info "se a larga não morreu: seu teto está alto demais para o volume que você subiu"
    info "(suba mais dias, registre mais partições, ou baixe o teto — é a DECISÃO 05)."
  fi
else fail "4" 15 "sem workgroup/database."; fi
linha

# ----------------------------------------------------- critério 6 (decisões) --
echo "${BOLD}Critério 6 — DECISOES.md (avaliação manual da justificativa)${OFF}"
if [ -f "$DECISOES" ]; then
  nd="$(grep -ciE 'DECIS[ÃA]O\s*0?[1-5]' "$DECISOES")"
  if [ "${nd:-0}" -ge 5 ]; then
    info "encontrei $nd decisões em $DECISOES — o CONTEÚDO é avaliado à mão (20%)."
    info "lembre: decisão diferente do gabarito, bem justificada, vale 10; igual sem justificar, no máximo 8."
  else
    info "achei só ${nd:-0} decisões em $DECISOES — faltam as 5 (01 a 05)."
  fi
else info "não achei $DECISOES — crie-o com uma frase por decisão (01 a 05)."; fi
linha

# ------------------------------------------------------------------- resumo --
echo "${BOLD}Resumo dos critérios automáticos: $notas / $total pontos-percentuais${OFF}"
info "faltam o critério 5 (rode ./verifica.sh --pos-destroy depois do destroy) e o 6 (manual)."
echo
echo "${BOLD}Cole o bloco abaixo no seu PR:${OFF}"
echo "  bucket=$BUCKET  db=$DB  table=$TABLE  wg=$WG  teto=$TETO"
echo "  criterios_automaticos=$notas/$total  data=$(date -u +%FT%TZ)"
