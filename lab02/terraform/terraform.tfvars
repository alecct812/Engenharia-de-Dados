# terraform.tfvars — Exercicio 02 (Aula 08)
# Grupo 02 · Turma 2026-2

sufixo = "grupo02"

# DECISAO 04 — registramos os 8 dias que subimos, incluindo o de hoje.
# A lista foi gerada a partir das pastas dt= que existem em dados/saida/, para
# garantir que o location de cada particao bate com a chave real no S3.
# Registrar menos seria expor um catalogo que descreve mal o lake: a consulta
# responderia um numero menor, sem erro nenhum.
dias_particao = [
  "2026-08-25",
  "2026-08-26",
  "2026-08-27",
  "2026-08-28",
  "2026-08-29",
  "2026-08-30",
  "2026-08-31",
  "2026-09-01"
]

# DECISAO 05 — 15 MiB, medido nesta conta.
# Medimos: uma particao 3.408.870 b · as 8 registradas 27.268.865 b.
# Cada dia pesa ~3,41 MB, entao o teto e uma politica: quantos dias uma consulta
# legitima pode varrer. 15.728.640 deixa passar ate 4 dias (13.633.876) e barra do
# 5o em diante (17.042.507), com folga de 2,09 MB para baixo e 1,31 MB para cima.
# Nao e o piso (10.485.760) porque o piso barraria 4 dias, e uma consulta de 3 dias
# varre 10.225.855 — 259.905 bytes abaixo dele, ou seja, ja operando na beirada.
# Nao e o topo (117.455.962) porque ele e 4,3x o lake inteiro: nunca tocaria.
teto_bytes = 15728640
