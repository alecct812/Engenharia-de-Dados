# DECISOES.md · Exercício 05 · grupo: 02

Turma 2026-2 · sufixo `grupo02` · `us-east-1` · executado em 2026-11-04. Hoje = 2026-11-04;
madrugada atrasada = 2026-11-01 (D-3); arquivo reenviado = 2026-10-30 (D-5). O `terraform.tfvars`
não é versionado; os valores declarados foram `modo_escrita = "sobrescrever"`,
`chave_dedup = "corrida_id"` e `janela_atraso_dias = 3`.

## DECISÃO 01: modo de escrita (`modo_escrita`)
Escolhemos `sobrescrever`. Rodando o job duas vezes, a tabela foi de 518.400 para 518.400 linhas,
com a madrugada em 11.137 nas duas consultas. Aceitamos que cada execução regrave as 30 pastas
(18.228.296 bytes), mesmo quando nenhuma linha mudou.

## DECISÃO 02: a chave da linha (`chave_dedup`)
Escolhemos `corrida_id`. Com o reenvio de 5 dias atrás, a tabela ficou com 518.400 linhas para
518.400 corridas distintas, a partir de uma raw com 535.680 linhas, e o job removeu 17.280
duplicatas. Aceitamos manter a primeira chegada de cada corrida, o que descartaria uma versão
corrigida que viesse no reenvio.

## DECISÃO 03: janela de atraso (`janela_atraso_dias`)
Escolhemos 3 dias, o maior atraso medido na raw (1.591 corridas com 3 dias, nenhuma acima disso).
A madrugada dos últimos 7 dias deu 11.137 corridas, com `fora_da_janela = 0`; pela janela, cada
execução diária relê 4 dias de chegada (o dia corrente e os 3 anteriores), embora este job, com
`DIAS=todos`, leia a raw inteira (535.680 linhas). Aceitamos que uma corrida com 4
dias de atraso ou mais fique fora da carga diária e dependa do backfill.

## DECISÃO 04: o backfill
Se uma corrida chegar com mais atraso do que a janela, o comando que conserta é
`./rodar-job.sh DIAS=2026-11-01` (com o dia do evento incompleto); ele reescreve 1 pasta e a
tabela fica com 518.400 linhas. Medido: das 30 pastas da trusted, só a de 2026-11-01 mudou, e a
madrugada continuou em 11.137. Ele não duplica porque a DECISÃO 01 troca a pasta em vez de
acrescentar, e a DECISÃO 02 reduz a uma linha a corrida que chegou em mais de uma pasta.
