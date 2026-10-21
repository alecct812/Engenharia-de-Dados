#!/usr/bin/env bash
# =============================================================================
# verifica.sh — Exercício 04 (Aula 21): trusted em Parquet particionado, com
# META DE CUSTO da pergunta da madrugada declarada e provada.
# Roda na SUA conta, da raiz do pacote. Imprime PASSA/FALHA por critério.
#
#   ./verificacao/verifica.sh                 # critérios 0 a 5 e 7 (stack no ar, job rodado)
#   ./verificacao/verifica.sh --pos-destroy   # critério 6 (rode depois do destroy)
# =============================================================================
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
TFDIR="${TFDIR:-$RAIZ/terraform}"
DECISOES="${DECISOES:-$RAIZ/DECISOES.md}"
REGIAO="${AWS_REGION:-us-east-1}"
META_MAX=1048576          # a meta tem de caber em 1 MiB (requisito do exercício)
TETO_MIN=10485760         # o Athena recusa teto abaixo de 10 MiB
POS=0; [ "${1:-}" = "--pos-destroy" ] && POS=1

G=$'\e[32m'; R=$'\e[31m'; D=$'\e[2m'; B=$'\e[1m'; X=$'\e[0m'
notas=0; total=0
linha(){ printf '%s\n' "----------------------------------------------------------------"; }
pass(){ notas=$((notas+$2)); total=$((total+$2)); printf "${G}PASSA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail(){ total=$((total+$2)); printf "${R}FALHA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
info(){ printf "${D}       %s${X}\n" "$1"; }
tfout(){ terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }
tfvar(){ grep -E "^\s*$1\s*=" "$TFDIR/terraform.tfvars" 2>/dev/null | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*)"?.*/\1/' | xargs; }

# Roda uma consulta no workgroup do grupo. Saída: ESTADO BYTES QID
athena(){
  local qid estado bytes
  qid="$(aws athena start-query-execution --work-group "$WG" --region "$REGIAO" \
         --query-string "$1" --query QueryExecutionId --output text 2>/dev/null)" || { echo "ERRO 0 -"; return; }
  while true; do
    estado="$(aws athena get-query-execution --query-execution-id "$qid" --region "$REGIAO" \
              --query QueryExecution.Status.State --output text)"
    case "$estado" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
    sleep 2
  done
  bytes="$(aws athena get-query-execution --query-execution-id "$qid" --region "$REGIAO" \
           --query QueryExecution.Statistics.DataScannedInBytes --output text)"
  echo "$estado ${bytes:-0} $qid"
}
resultado(){ aws athena get-query-results --query-execution-id "$1" --region "$REGIAO" \
               --query 'ResultSet.Rows[1:].Data[*].VarCharValue' --output text; }
motivo(){ aws athena get-query-execution --query-execution-id "$1" --region "$REGIAO" \
            --query QueryExecution.Status.StateChangeReason --output text; }

# ------------------------------------------------------------ pós-destroy -----
if [ "$POS" = "1" ]; then
  echo "${B}Critério 6 — destroy limpo${X}"; linha
  SUF="$(tfvar sufixo)"
  sobra=""
  aws s3api head-bucket --bucket "eda-a21-lake-$SUF" --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra bucket"
  aws glue get-job --job-name "eda-a21-trusted-$SUF" --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra job"
  aws glue get-database --name "eda_a21_$SUF" --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra database"
  aws athena get-work-group --work-group "eda-a21-wg-$SUF" --region "$REGIAO" >/dev/null 2>&1 && sobra="$sobra workgroup"
  aws iam get-role --role-name "eda-a21-glue-$SUF" >/dev/null 2>&1 && sobra="$sobra papel"
  if [ -z "$sobra" ]; then pass "6" 10 "nenhum recurso eda-a21-*-$SUF sobrou."
  else fail "6" 10 "sobrou:$sobra"; fi
  linha; printf "${B}Critério 6: %s/10%%${X}\n" "$notas"; exit 0
fi

echo "${B}Exercício 04 — verificação (região $REGIAO)${X}"; linha

BUCKET="$(tfout bucket_name)"; DB="$(tfout database_name)"; TABELA="$(tfout trusted_table_name)"
WG="$(tfout workgroup_name)"; META="$(tfout meta_bytes_madrugada)"; TETO="$(tfout teto_bytes)"
if [ -z "$BUCKET" ] || [ -z "$TABELA" ] || [ -z "$WG" ]; then
  fail "0" 0 "não li os outputs de contrato — rodou o terraform apply? (TFDIR=$TFDIR)"; exit 2
fi

# --------------------------------------------- critério 0 (eliminatório) -----
echo "${B}Critério 0 — Terraform com backend remoto, trusted em Parquet (ELIMINATÓRIO)${X}"
if ! grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "não achei backend \"s3\" — o estado precisa estar no backend remoto."; exit 2
fi
SERDE="$(aws glue get-table --database-name "$DB" --name "$TABELA" --region "$REGIAO" \
         --query Table.StorageDescriptor.SerdeInfo.SerializationLibrary --output text 2>/dev/null)"
if [ "${SERDE##*.}" != "ParquetHiveSerDe" ]; then
  fail "0" 0 "a trusted não está declarada como Parquet (SerDe: ${SERDE:-nenhum})."; exit 2
fi
printf "${G}OK${X}     [0]  backend s3 e trusted em Parquet\n"; linha

# ------------------------------------- critério 1 (trusted particionada) -----
echo "${B}Critério 1 — a trusted está declarada e particionada por data${X}"
CHAVES="$(aws glue get-table --database-name "$DB" --name "$TABELA" --region "$REGIAO" \
          --query 'Table.PartitionKeys[].Name' --output text | tr '\t' ',')"
NCOL="$(aws glue get-table --database-name "$DB" --name "$TABELA" --region "$REGIAO" \
        --query 'length(Table.StorageDescriptor.Columns)' --output text)"
NCHV="$(echo "$CHAVES" | tr ',' '\n' | grep -c .)"
if [ "${CHAVES%%,*}" = "dt" ] && [ $((NCOL + NCHV)) -eq 11 ]; then
  pass "1" 15 "partição: $CHAVES · $NCOL colunas + $NCHV chave(s) = as 10 colunas e o dt."
else
  fail "1" 15 "partição: '${CHAVES:-nenhuma}' · $NCOL colunas. Esperado: dt como 1ª chave e as 10 colunas da trusted."
fi
linha

# ------------------------------------------- critério 2 (dado completo) -----
echo "${B}Critério 2 — a trusted tem os 30 dias, sem perder corrida${X}"
read -r E2 B2 Q2 <<<"$(athena "SELECT count(*), count(DISTINCT dt) FROM $DB.$TABELA")"
if [ "$E2" = "SUCCEEDED" ]; then
  read -r N2 D2 <<<"$(resultado "$Q2")"
  if [ "$N2" = "518400" ] && [ "$D2" = "30" ]; then pass "2" 10 "518400 corridas em 30 dias."
  else fail "2" 10 "achei $N2 corridas em $D2 dias (esperado 518400 em 30)."
       info "count 0? faltou registrar as partições (DECISÃO 05) ou rodar o job."; fi
else fail "2" 10 "a contagem não rodou ($E2): $(motivo "$Q2")"; fi
linha

# ------------------------------------- critério 3 (sem arquivos pequenos) -----
echo "${B}Critério 3 — no máximo 4 arquivos por pasta de partição${X}"
LISTA="$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix trusted/corridas/ --region "$REGIAO" \
         --query 'Contents[?ends_with(Key, `.parquet`)].[Key,Size]' --output text 2>/dev/null)"
NARQ="$(echo "$LISTA" | grep -c '\.parquet' || true)"
MAXP="$(echo "$LISTA" | awk -F'\t' 'NF{sub(/\/[^\/]*$/, "", $1); n[$1]++} END{m=0; for(k in n) if(n[k]>m) m=n[k]; print m}')"
TOT="$(echo "$LISTA" | awk -F'\t' '{s+=$2} END{print s+0}')"
if [ "${NARQ:-0}" -gt 0 ] && [ "${MAXP:-99}" -le 4 ]; then
  pass "3" 10 "$NARQ arquivos, no máximo $MAXP por pasta, $TOT bytes no total."
else
  fail "3" 10 "$NARQ arquivos, até ${MAXP:-?} numa pasta. Arquivos pequenos de novo (Aula 19)."
fi
linha

# ------------------------------------------ critério 4 (a meta de custo) -----
echo "${B}Critério 4 — a pergunta da madrugada (7 dias) cabe na META declarada${X}"
DESDE="$(python3 -c 'import datetime as d; print(d.date.today() - d.timedelta(days=6))')"
SQL4="SELECT bairro, count(*) AS corridas, round(sum(valor), 2) AS receita FROM $DB.$TABELA WHERE dt >= '$DESDE' AND faixa_hora BETWEEN 0 AND 5 GROUP BY bairro"
read -r E4 B4 Q4 <<<"$(athena "$SQL4")"
if [ "$E4" = "SUCCEEDED" ]; then
  CORR="$(resultado "$Q4" | awk '{s+=$(NF-1)} END{print s+0}')"
  info "meta declarada: $META bytes · Data scanned: $B4 bytes · corridas: $CORR"
  if [ "${META:-0}" -gt "$META_MAX" ]; then
    fail "4" 25 "a meta ($META) passa de 1 MiB ($META_MAX): o requisito é caber em 1 MiB."
  elif [ "$CORR" != "11137" ]; then
    fail "4" 25 "a resposta mudou: $CORR corridas (esperado 11137). Confira o dado e o DESDE."
  elif [ "$B4" -le "$META" ]; then
    pass "4" 25 "leu $B4 bytes, dentro da meta de $META. Resposta certa: 11137 corridas."
  else
    fail "4" 25 "leu $B4 bytes, acima da meta de $META."
    info "a consulta abriu pastas demais (partição) ou arquivos demais (rodapés)?"
  fi
else fail "4" 25 "a consulta não rodou ($E4): $(motivo "$Q4")"; fi
linha

# ------------------------------------------------ critério 5 (o freio) -----
echo "${B}Critério 5 — o teto do workgroup existe e barra a consulta larga${X}"
CUT="$(aws athena get-work-group --work-group "$WG" --region "$REGIAO" \
       --query WorkGroup.Configuration.BytesScannedCutoffPerQuery --output text)"
ENF="$(aws athena get-work-group --work-group "$WG" --region "$REGIAO" \
       --query WorkGroup.Configuration.EnforceWorkGroupConfiguration --output text)"
SQL5="SELECT max(corrida_id), max(motorista_id), max(passageiro_id), max(inicio), max(fim), max(distancia_km), max(duracao_min), max(valor) FROM $DB.$TABELA"
read -r E5 B5 Q5 <<<"$(athena "$SQL5")"
if [ "$CUT" != "$TETO" ] || [ "$ENF" != "True" ]; then
  fail "5" 10 "o workgroup tem teto $CUT (output: $TETO) e enforce=$ENF. O teto tem de valer, e valer para todos."
elif [ "$CUT" -lt "$TETO_MIN" ]; then
  fail "5" 10 "teto $CUT abaixo do mínimo do Athena ($TETO_MIN)."
elif [ "$E5" = "SUCCEEDED" ]; then
  fail "5" 10 "a consulta de todas as colunas PASSOU ($B5 bytes): o teto de $CUT não freia nada."
else
  pass "5" 10 "teto de $CUT bytes: a consulta de todas as colunas foi barrada ($E5)."
  info "$(motivo "$Q5" | cut -c1-110)"
fi
linha

# ---------------------------------------------- critério 7 (decisões) -----
echo "${B}Critério 7 — DECISOES.md (avaliação manual)${X}"
if [ -f "$DECISOES" ]; then
  nd="$(grep -ciE 'DECIS[ÃA]O\s*0?[1-5]' "$DECISOES")"
  info "encontrei $nd decisões em $DECISOES — o conteúdo é avaliado à mão (20%)."
else info "não achei $DECISOES — uma frase por decisão (01 a 05), cada uma com número medido."; fi
linha

echo "${B}Critérios automáticos: $notas / $total pontos-percentuais${X}"
info "faltam o critério 6 (./verificacao/verifica.sh --pos-destroy) e o 7 (manual)."
echo
echo "${B}Cole no seu PR:${X}"
echo "  particao=$CHAVES  arquivos=$NARQ  meta=$META  lido_madrugada_7d=${B4:-?}  teto=$CUT  criterios_auto=$notas/$total  data=$(date -u +%FT%TZ)"
