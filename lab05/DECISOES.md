# DECISOES.md · Exercício 05: o pipeline que pode rodar de novo

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Conta `325583868777` · executado em 2026-11-04 · Terraform v1.15.8 · provider AWS 5.100.0 · Glue 4.0

Todos os números abaixo foram medidos nesta conta, no cru carregado pelo `carregar-raw.sh`:
hoje é 2026-11-04, a madrugada atrasada é a de 2026-11-01 (D-3) e o arquivo reenviado é o
de 2026-10-30 (D-5), que chegou de novo em 2026-10-31. A pergunta de referência é a
madrugada dos últimos 7 dias (`dt >= '2026-10-29'` e `faixa_hora` entre 0 e 5).

Como o `terraform.tfvars` não é versionado, os valores das três variáveis ficam registrados
aqui:

```
modo_escrita       = "sobrescrever"
chave_dedup        = "corrida_id"
janela_atraso_dias = 3
```

## DECISÃO 01: modo de escrita (`modo_escrita`)

Escolhemos `sobrescrever`, que troca apenas as pastas `dt=` que a execução escreve. Rodando
o job duas vezes, a tabela foi de 518.400 para 518.400 linhas, e a madrugada ficou em 11.137
nas duas consultas; a terceira execução, disparada pelo `verifica.sh`, manteve os mesmos
números. O que se aceita perder é trabalho repetido: como a carga diária processa a raw
inteira, cada execução regrava as 30 pastas (30 arquivos, 18.228.296 bytes), mesmo quando
nenhuma linha mudou. A troca é visível no S3: o arquivo de `dt=2026-11-01` saiu da primeira
execução com o nome `part-00000-5eaf459b…` e foi substituído na segunda por
`part-00000-ee912358…`, com os mesmos 607.433 bytes, sem que um segundo arquivo se somasse
ao primeiro.

## DECISÃO 02: a chave da linha (`chave_dedup`)

Escolhemos `corrida_id`. Com o reenvio de 5 dias atrás, a raw ficou com 535.680 linhas para
518.400 corridas distintas; o job removeu 17.280 duplicatas, exatamente o arquivo de
2026-10-30 lido pela segunda vez, e a tabela ficou com 518.400 linhas para 518.400 corridas
distintas. A deduplicação é o que o modo de escrita não resolve, porque as duas cópias
entram na mesma execução: sobrescrever sem chave seria estável, mas estável no número
errado. O que se aceita perder é a versão mais nova de uma corrida reenviada, já que o job
mantém a primeira chegada; neste cru as duas cópias são idênticas, e a perda é nula, mas um
reenvio com valores corrigidos seria descartado.

## DECISÃO 03: janela de atraso (`janela_atraso_dias`)

Escolhemos 3 dias, o menor valor que cobre o atraso medido na raw. Comparando o dia de
chegada (`dt`) com o dia do evento, a raw tem 516.809 corridas com atraso 0, 17.280 com
atraso 1 (o reenvio) e 1.591 com atraso 3 (a madrugada de 2026-11-01), e nenhuma acima
disso. Com essa janela, o relatório do job registrou `fora_da_janela = 0`, e a madrugada
dos últimos 7 dias deu 11.137 corridas. Cada execução diária relê 4 dias de chegada (o dia
corrente e os 3 anteriores) para refazer os 4 dias de evento que ainda podem receber dado
atrasado; nesta carga, com `DIAS=todos`, o job leu a raw inteira (535.680 linhas). O que se
aceita perder é a corrida que chegar com 4 dias de atraso ou mais: ela fica fora da carga
diária, contada em `fora_da_janela`, e passa a depender do backfill da decisão seguinte.
Uma janela de 7 dias também traria as 11.137, mas obrigaria cada execução incremental a
reler 8 dias de chegada para cobrir um atraso que o cru nunca apresentou.

## DECISÃO 04: o backfill

Se uma corrida chegar com mais atraso do que a janela, o comando que conserta é
`./rodar-job.sh DIAS=2026-11-01`, trocando a data pelo dia do evento incompleto; ele
reescreve 1 pasta e a tabela fica com 518.400 linhas. Medimos isso rodando o backfill do dia
da madrugada atrasada depois do `verifica.sh`: o relatório registrou
`dias_gravados_neste_run = 1` e 17.280 linhas gravadas, das quais 1.591 na madrugada. A
listagem da trusted antes e depois mostrou que só o arquivo de `dt=2026-11-01` mudou,
enquanto os outros 29 permaneceram com o mesmo nome e o mesmo horário. A madrugada dos 7
dias continuou em 11.137, e a tabela, com 518.400 linhas para 518.400 corridas distintas. O
backfill não duplica por dois motivos que dependem das decisões anteriores: em
`sobrescrever`, a pasta do dia é trocada, e não acrescida; e, como ele aceita qualquer
atraso, a chave `corrida_id` reduz a uma linha as corridas que chegaram em mais de uma pasta.
O custo é ler a raw inteira (535.680 linhas) para gravar um único dia: a execução levou 100
segundos, contra 109 a 164 das cargas diárias.
