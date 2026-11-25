# DECISOES.md — Exercício 06 · grupo: 02

Turma 2026-2 · sufixo `grupo02` · `us-east-1` · executado em 2026-11-25 (hoje = 2026-11-25; últimos
7 dias desde 2026-11-19). O `terraform.tfvars` não é versionado; os valores declarados foram
`escopo_prefeitura = "tabela"`, `colunas_ocultas_analista = ["motorista_id", "passageiro_id"]` e o
`contrato_refined` da DECISÃO 03.

## DECISÃO 01 — o alcance da Prefeitura na refined (`escopo_prefeitura`)
Escolhemos `tabela`, porque a Prefeitura é consumidora de fora e não pode ver nenhum id. Com essa escolha, se alguém criar amanhã uma tabela nova na refined, a Prefeitura não a enxerga até alguém conceder (a `teste_com_motorista` que criamos na refined deu `TABLE_NOT_FOUND` como ela);
a madrugada dos últimos 7 dias, lida como a Prefeitura, deu 11.137 corridas. Aceitamos que cada tabela nova do painel espere uma concessão a mais no Terraform.

## DECISÃO 02 — as colunas que a analista não vê (`colunas_ocultas_analista`)
Escondemos `motorista_id` e `passageiro_id`, as duas que ligam a corrida a uma pessoa. A analista continua lendo 9 das 11 colunas; `SELECT passageiro_id` como ela deu `RECUSADO` (`COLUMN_NOT_FOUND`), e `SELECT motorista_id` também.
Deixamos visível `corrida_id` porque ela precisa disso para achar a corrida reclamada e conferir duplicata (518.400 linhas para 518.400 `corrida_id` distintos). Aceitamos que ela não consiga dizer se as reclamações se concentram num mesmo motorista.

## DECISÃO 03 — o contrato da refined (`contrato_refined`)
A descrição diz "Corridas e receita da madrugada (0h a 5h59, UTC) por bairro e por dia, somadas a partir da trusted; sem nenhum id de corrida, motorista ou passageiro." (150 caracteres). Um consumidor que só ler o catálogo sabe o que a tabela responde, o grão (uma linha por bairro e dia) e que a madrugada é em UTC, não no horário do Recife, e sabe que a tabela não tem nenhum id de corrida, motorista ou passageiro.
O dono é "Engenharia de Dados - grupo 02", e a tabela muda diariamente, depois do job da trusted, sobrescrevendo as pastas `dt=` que recalcula. Aceitamos que o número de um dia passado mude quando chega dado atrasado, como a madrugada de 2026-11-22, que chegou 3 dias depois e está nas 11.137.
