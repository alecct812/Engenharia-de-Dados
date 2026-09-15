#!/usr/bin/env bash
# =============================================================================
# verifica.sh — Exercício 03 (Aula 12): refatorar em módulo, com plan LIMPO.
# Roda na SUA conta, na pasta refatorada. Imprime PASSA/FALHA por critério.
#
#   ./verifica.sh                 # critérios 0 a 4 e 6 (stack no ar, refatorada)
#   ./verifica.sh --pos-destroy   # critério 5 (rode depois do destroy)
# =============================================================================
set -uo pipefail

TFDIR="${TFDIR:-../terraform}"
REGIAO="${AWS_REGION:-us-east-1}"
DECISOES="${DECISOES:-../DECISOES.md}"
POS=0; [ "${1:-}" = "--pos-destroy" ] && POS=1

G=$'\e[32m'; R=$'\e[31m'; D=$'\e[2m'; B=$'\e[1m'; X=$'\e[0m'
notas=0; total=0
linha(){ printf '%s\n' "----------------------------------------------------------------"; }
pass(){ notas=$((notas+$2)); total=$((total+$2)); printf "${G}PASSA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
fail(){ total=$((total+$2)); printf "${R}FALHA${X}  [%s]  (%s%%)  %s\n" "$1" "$2" "$3"; }
info(){ printf "${D}       %s${X}\n" "$1"; }
tfout(){ terraform -chdir="$TFDIR" output -raw "$1" 2>/dev/null; }
tfvar(){ grep -E '^\s*sufixo' "$TFDIR/terraform.tfvars" 2>/dev/null | sed -E 's/.*"([^"]+)".*/\1/'; }

# ------------------------------------------------------------ pós-destroy -----
if [ "$POS" = "1" ]; then
  echo "${B}Critério 5 — destroy limpo${X}"; linha
  SUF="$(tfvar)"
  orf="$(aws s3 ls --region "$REGIAO" 2>/dev/null | grep -E "eda-a12-${SUF}-(lake|results)\b" || true)"
  if [ -z "$orf" ]; then pass "5" 15 "nenhum bucket órfão."
  else fail "5" 15 "há bucket órfão:"; echo "$orf"; fi
  linha; printf "${B}Critério 5: %s/15%%${X}\n" "$notas"; exit 0
fi

echo "${B}Exercício 03 — verificação da refatoração (região $REGIAO)${X}"; linha

# --------------------------------------------- critério 0 (eliminatório) -----
echo "${B}Critério 0 — módulo + backend remoto + workspace (ELIMINATÓRIO)${X}"
if ! grep -rqE '^\s*module\s+"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "não achei um bloco module na raiz — a stack não foi embrulhada em módulo."; exit 2
fi
if [ ! -d "$TFDIR/modules" ]; then
  fail "0" 0 "não achei a pasta modules/ — onde está o módulo?"; exit 2
fi
if ! grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf 2>/dev/null; then
  fail "0" 0 "não achei backend \"s3\" — o estado ainda é local."; exit 2
fi
printf "${G}OK${X}     [0]  módulo, backend s3 e pasta modules/ presentes\n"; linha

# ------------------------------------------ critério 1 (plan LIMPO · 30%) -----
echo "${B}Critério 1 — plan LIMPO (o coração do exercício)${X}"
SUF="$(tfvar)"
terraform -chdir="$TFDIR" plan -detailed-exitcode -var="sufixo=$SUF" >/tmp/a12plan.txt 2>&1
rc=$?
if [ "$rc" = "0" ]; then
  pass "1" 30 "No changes — a refatoração não recriou nada."
elif [ "$rc" = "2" ]; then
  fail "1" 30 "o plan quer MUDAR algo — você recriou recurso. Veja /tmp/a12plan.txt"
  grep -E '# .* will be| will be (created|destroyed|replaced)' /tmp/a12plan.txt | head -6
  info "provável: você aplicou antes do state mv, ou o módulo mudou algum nome."
else
  fail "1" 30 "o plan deu erro (rc=$rc). Veja /tmp/a12plan.txt"
  tail -4 /tmp/a12plan.txt
fi
linha

# ------------------------------------------- critério 2 (estado remoto) -----
echo "${B}Critério 2 — o estado está no backend remoto${X}"
if [ -f "$TFDIR/terraform.tfstate" ] && grep -q '"resources"' "$TFDIR/terraform.tfstate" 2>/dev/null; then
  fail "2" 15 "há um terraform.tfstate LOCAL com recursos — o estado não migrou."
else
  if grep -rqE 'backend\s+"s3"' "$TFDIR"/*.tf; then pass "2" 15 "backend s3 configurado e sem estado local."
  else fail "2" 15 "backend não é s3."; fi
fi
linha

# ------------------------------------------------ critério 3 (workspace) -----
echo "${B}Critério 3 — um workspace nomeado foi usado${X}"
ws="$(terraform -chdir="$TFDIR" workspace list 2>/dev/null | sed 's/[* ]//g' | grep -v '^default$' | grep -v '^$' | tr '\n' ' ')"
if [ -n "$ws" ]; then pass "3" 10 "workspace(s) além do default: $ws"
else
  if grep -rqE 'terraform\.workspace' "$TFDIR"/*.tf "$TFDIR"/modules/*/*.tf 2>/dev/null; then
    pass "3" 10 "código workspace-aware (usa terraform.workspace)."
  else fail "3" 10 "nenhum workspace nomeado e o código não usa terraform.workspace."; fi
fi
linha

# ---------------------------------------------- critério 4 (contrato) -----
echo "${B}Critério 4 — os cinco outputs de contrato preservados${X}"
faltou=""
for o in bucket_name database_name table_name workgroup_name teto_bytes; do
  [ -z "$(tfout "$o")" ] && faltou="$faltou $o"
done
if [ -z "$faltou" ]; then pass "4" 10 "os cinco outputs continuam lá."
else fail "4" 10 "sumiram na refatoração:$faltou"; fi
linha

# ---------------------------------------------- critério 6 (decisões) -----
echo "${B}Critério 6 — DECISOES.md (avaliação manual)${X}"
if [ -f "$DECISOES" ]; then
  nd="$(grep -ciE 'DECIS[ÃA]O\s*0?[1-5]' "$DECISOES")"
  info "encontrei $nd decisões em $DECISOES — o conteúdo é avaliado à mão (20%)."
else info "não achei $DECISOES — crie-o com uma frase por decisão (01 a 05)."; fi
linha

echo "${B}Critérios automáticos: $notas / $total pontos-percentuais${X}"
info "faltam o critério 5 (./verifica.sh --pos-destroy) e o 6 (manual)."
echo
echo "${B}Cole no seu PR:${X}"
echo "  plan_limpo=$([ "$rc" = "0" ] && echo sim || echo NAO)  criterios_auto=$notas/$total  data=$(date -u +%FT%TZ)"
