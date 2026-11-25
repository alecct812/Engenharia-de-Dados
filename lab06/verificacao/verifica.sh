#!/usr/bin/env bash
# verifica.sh — Exercício 06 (Aula 29). Rode da raiz do pacote, na conta do grupo, depois de
# ./carregar-raw.sh e ./rodar-jobs.sh:
#   ./verificacao/verifica.sh                 critérios 0 a 4 (pergunta como a Prefeitura e como a analista)
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
BANCO="eda_a29_$SUFIXO"

# ------------------------------------------------------------- critério 5 (pós-destroy)
if [[ "${1:-}" == "--pos-destroy" ]]; then
  sobra=""
  aws s3api head-bucket --bucket "eda-a29-lake-$SUFIXO" >/dev/null 2>&1 && sobra="$sobra bucket"
  for c in raw trusted refined; do
    aws glue get-database --name "${BANCO}_$c" >/dev/null 2>&1 && sobra="$sobra database_$c"
  done
  for j in trusted refined; do
    aws glue get-job --job-name "eda-a29-$SUFIXO-$j" >/dev/null 2>&1 && sobra="$sobra job_$j"
  done
  aws athena get-work-group --work-group "eda-a29-$SUFIXO-wg" >/dev/null 2>&1 && sobra="$sobra workgroup"
  for p in glue lf prefeitura analista; do
    aws iam get-role --role-name "eda-a29-$SUFIXO-$p" >/dev/null 2>&1 && sobra="$sobra papel_$p"
  done
  reg=$(aws lakeformation list-resources --query "ResourceInfoList[?contains(ResourceArn, 'eda-a29-lake-$SUFIXO')].ResourceArn" --output text 2>/dev/null)
  [[ -n "$reg" && "$reg" != "None" ]] && sobra="$sobra registro_lake_formation"
  if [[ -z "$sobra" ]]; then passa 5 10 "destroy limpo: nenhum recurso eda-a29-$SUFIXO sobrou"
  else falha 5 10 "sobraram:$sobra"; exit 1; fi
  exit 0
fi

out() { terraform -chdir=terraform output -raw "$1" 2>/dev/null; }
BUCKET="$(out bucket)"; WG="$(out workgroup)"
[[ -n "$BUCKET" && -n "$WG" ]] || { echo "sem outputs: rode terraform apply antes"; exit 2; }
RAW="$(out database_raw)"; TRU="$(out database_trusted)"; REF="$(out database_refined)"

# como <perfil> <comando...>: roda o comando com as credenciais do papel do perfil
como() {
  local perfil="$1"; shift
  local arn; arn="$(out "papel_$perfil")"
  local cred; cred=$(aws sts assume-role --role-arn "$arn" --role-session-name "verifica-$perfil" --duration-seconds 900 \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text) || return 1
  local ak sk st; read -r ak sk st <<<"$cred"
  ( export AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$st"; unset AWS_PROFILE; "$@" )
}
# athena "<SQL>": imprime a primeira linha de resultado (colunas separadas por tab), ou RECUSADO
athena() {
  local id st
  id=$(aws athena start-query-execution --work-group "$WG" --query-string "$1" --query QueryExecutionId --output text 2>/dev/null) \
    || { echo "RECUSADO"; return 0; }
  while :; do
    st=$(aws athena get-query-execution --query-execution-id "$id" --query QueryExecution.Status.State --output text)
    case "$st" in SUCCEEDED) break;; FAILED|CANCELLED) echo "RECUSADO"; return 0;; esac
    sleep 2
  done
  aws athena get-query-results --query-execution-id "$id" --query 'ResultSet.Rows[1].Data[*].VarCharValue' --output text
}

HOJE=$(aws s3 ls "s3://$BUCKET/raw/corridas/" | awk '{print $2}' | sed -n 's#^dt=\(.*\)/$#\1#p' | sort | tail -1)
[[ -n "$HOJE" ]] || { echo "raw vazia: rode ./carregar-raw.sh"; exit 2; }
DESDE=$(python3 -c "import datetime as d; print(d.date.fromisoformat('$HOJE') - d.timedelta(days=6))")

# ------------------------------------------------------------- critério 0 (elimina)
tipo=$(python3 -c "import json;print(json.load(open('terraform/.terraform/terraform.tfstate'))['backend']['type'])" 2>/dev/null)
classe=$(aws glue get-table --database-name "$REF" --name madrugada_bairro --query 'Table.Parameters.classification' --output text 2>/dev/null)
bancos=0
for b in "$RAW" "$TRU" "$REF"; do aws glue get-database --name "$b" >/dev/null 2>&1 && bancos=$((bancos + 1)); done
if [[ "$tipo" == "s3" && "$classe" == "parquet" && "$bancos" == 3 ]]; then
  echo "OK     [0]  (elimina)  backend remoto s3, três databases (um por camada) e a refined em Parquet"
else
  echo "FALHA  [0]  (elimina)  backend=${tipo:-local} databases=$bancos/3 refined=${classe:-?}: nada mais conta"; exit 1
fi

# ------------------------------------------------------------- critério 1: a Prefeitura lê a refined
p1=$(como prefeitura athena "SELECT sum(corridas) FROM $REF.madrugada_bairro WHERE dt >= '$DESDE'")
if [[ "$p1" == "$CERTA" ]]; then passa 1 20 "a Prefeitura lê a refined: $p1 corridas na madrugada dos últimos 7 dias"
else falha 1 20 "a Prefeitura leu '$p1' na refined; o certo é $CERTA (RECUSADO = faltou a permissão da DECISÃO 01)"; fi

# ------------------------------------------------------------- critério 2: e só a refined
p2t=$(como prefeitura athena "SELECT count(*) FROM $TRU.corridas WHERE dt = '$HOJE'")
p2r=$(como prefeitura athena "SELECT count(*) FROM $RAW.corridas WHERE dt = '$HOJE'")
if como prefeitura aws s3 ls "s3://$BUCKET/refined/" >/dev/null 2>&1; then p2s="leu"; else p2s="RECUSADO"; fi
if [[ "$p2t" == RECUSADO && "$p2r" == RECUSADO && "$p2s" == RECUSADO ]]; then
  passa 2 25 "a Prefeitura não lê a trusted, nem a raw, nem o S3 direto"
else
  falha 2 25 "a Prefeitura leu o que não devia: trusted=$p2t raw=$p2r s3=$p2s (trusted lida = a tabela ainda dá acesso automático, IAMAllowedPrincipals)"
fi

# ------------------------------------------------------------- critério 3: a analista lê a trusted, sem passageiro_id
a3=$(como analista athena "SELECT count(bairro) FROM $TRU.corridas")
a3p=$(como analista athena "SELECT passageiro_id FROM $TRU.corridas WHERE dt = '$HOJE' LIMIT 1")
if [[ "$a3" == "$TOTAL" && "$a3p" == RECUSADO ]]; then
  passa 3 15 "a analista lê a trusted ($a3 corridas) e não vê passageiro_id"
else
  falha 3 15 "a analista: count(bairro)='$a3' (o certo: $TOTAL); passageiro_id: '$a3p' (o certo: RECUSADO)"
fi

# ------------------------------------------------------------- critério 4: o contrato da refined
contrato=$(aws glue get-table --database-name "$REF" --name madrugada_bairro --output json 2>/dev/null | python3 -c '
import json, sys
t = json.load(sys.stdin)["Table"]
desc = (t.get("Description") or "").strip()
dono = (t.get("Parameters", {}).get("dono") or "").strip()
cols = t["StorageDescriptor"]["Columns"]
sem = [c["Name"] for c in cols if not (c.get("Comment") or "").strip()]
ok = len(desc) >= 40 and dono != "" and not sem
faltam = ",".join(sem) or "-"
print(("OK" if ok else "NAO") + "|%d|%s|%s" % (len(desc), dono, faltam))' 2>/dev/null)
IFS='|' read -r c4 c4d c4o c4s <<<"${contrato:-NAO|0||?}"
if [[ "$c4" == OK ]]; then passa 4 10 "o contrato da refined está no catálogo: descrição ($c4d caracteres), dono '$c4o', comentário em toda coluna"
else falha 4 10 "contrato incompleto: descrição=$c4d caracteres (mínimo 40), dono='$c4o', colunas sem comentário: $c4s"; fi

echo
echo "Critérios automáticos: $pontos / 70 pontos-percentuais"
echo "Falta o que o script não mede: o critério 5 (rode com --pos-destroy depois do destroy) e o DECISOES.md (20%)."
echo
echo "evidência: sufixo=$SUFIXO hoje=$HOJE prefeitura_refined=$p1 prefeitura_trusted=$p2t prefeitura_raw=$p2r prefeitura_s3=$p2s analista_trusted=$a3 analista_passageiro=$a3p $(terraform -chdir=terraform output -json decisoes 2>/dev/null | tr -d ' \n')"
