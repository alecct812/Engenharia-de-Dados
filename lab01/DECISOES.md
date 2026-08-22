# DECISOES.md — Exercício 01: o schema é seu

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Stack `eda-a04-grupo02` · executado em 2026-08-17 · Athena engine v3

Uma frase por decisão, e sob ela a medição que a sustenta. Todos os números saíram de
consulta nesta conta; onde a medição contrariou o que supúnhamos, está dito. A evidência
bruta está em `EVIDENCIA.md`.

---

## DECISÃO 01 — o tipo de `valor`: `decimal(10,2)`

Declaramos `decimal(10,2)` porque preço de corrida é um contrato de dois centavos e
binary float não guarda dinheiro, e **aceitamos perder a disponibilidade da coluna**: os
1,42% que chegam como `"8,43"` não cabem no tipo, e enquanto a origem não for corrigida
nenhuma consulta que leia `valor` responde — preferimos isso a `string`, que não apaga o
problema, só o empurra para o `cast` de toda consulta futura, onde ele quebra longe de
quem poderia consertar a origem.

> **Medido** na partição de hoje: 245 das 17.280 corridas (1,42%) trazem `valor` com
> vírgula decimal. A linha continua íntegra no S3, e a corrida aparece normalmente em
> qualquer consulta que não leia `valor`.

## DECISÃO 02 — o tipo de `data_corrida` e `fim`: `timestamp`

Supúnhamos que o ISO-8601 com `T` e `Z` não seria parseado e que o `SELECT` voltaria
nulo; **testamos e voltou timestamp de verdade**, então ficamos com `timestamp` — que
deixa `date_diff` e `hour()` responderem sem `cast` — e aceitamos perder o fuso, porque
o Athena descarta a marca de UTC e, no dia em que uma origem mandar `-03:00`, o offset
some sem erro e as duas viram a mesma hora.

> **Medido:** `SELECT corrida_id, data_corrida, fim FROM corridas WHERE dt = '2026-08-17'
> LIMIT 5` devolveu `c-00501121 | 2026-08-17 00:47:19.000 | 2026-08-17 00:53:13.000`,
> sem nenhum nulo.

## DECISÃO 03 — `ignore.malformed.json`: `false`

Preferimos **barulho**, e quem paga é quem lê `valor` — a conta vai para quem depende da
coluna quebrada, no minuto em que ela quebra, e não para ninguém —, porque o silêncio
devolveria `sum(valor)` com cara de saúde perfeita e cerca de R$ 4,3 mil por dia a
menos, que é exatamente o "erro que não dá erro" da Aula 03, e porque declarar
`decimal(10,2)` para depois deixar o motor nular o que não cabe seria escrever um
contrato e renunciar a cobrá-lo.

> **Medido em três deploys:** `ignore.malformed.json` é **inerte neste dado** — `true` e
> `false` deram resultado idêntico, porque ele cobre a *linha* que não é JSON válido e
> não existe nenhuma (`"8,43"` é JSON válido com valor inválido). Quem decide barulho
> contra silêncio é `use.null.for.invalid.data`, e a falha que ele produz é **por
> coluna**: com ambas em `false`, `SELECT count(*)` e o painel de bairros continuaram
> respondendo, e o erro nomeia arquivo, coluna, valor ofensor e correção. Declaramos as
> duas em `false`, na tabela **e nas três partições** — a leitura usa o SerDe da
> partição, não o da tabela. Tabela completa em `EVIDENCIA.md`, seção 3.

## DECISÃO 04 — quantas das 30 partições: `3`

Declaramos três porque é o teto da ferramenta e não da vontade — o `deploy.sh` passa
exatamente `DataParticao1/2/3`, e uma quarta exigiria um parâmetro que, sem `Default`,
impediria a stack de subir e, com `Default`, versionaria uma data no repositório —, e
aceitamos que as outras 27 **não existam para quem pergunta**: seguem pagas e íntegras
no S3, fora do catálogo, e `SELECT count(*)` enxerga 3 dias, não 30.

> **No dia 31** o gerador grava `dt=2026-08-18` no S3 e nada acontece: sem erro, sem
> alerta, a consulta segue respondendo com os mesmos três dias de sempre e o número
> apenas para de crescer — a pior falha possível, a que responde. Ela só desaparece se
> alguém assumir o custo recorrente de `ALTER TABLE ADD PARTITION` a cada carga, ou
> trocar o registro manual por partition projection.

## DECISÃO 05 — o teto de bytes por consulta: `10.600.000`

O número saiu da medição das partições no S3 — é 2,70× a maior partição e 90,1% de tudo
que o catálogo expõe, então cabe um dia com folga e o full scan estoura —, e não é o
piso 10.485.760 porque esse é um limite da AWS e não uma medida nossa, nem o topo
117.655.605 porque esse descreve o S3 e não o catálogo: com 3 partições registradas
nenhuma consulta varre mais de 11.765.273 bytes, e um teto acima disso seria um freio
decorativo, igual aos 10 GiB que o Lab 01 nunca tocou.

> **Medido:** uma partição 3.921.495 b · as 3 registradas 11.765.273 b · lake inteiro no
> S3 117.655.606 b. Com o teto no ar, a estreita respondeu 10 linhas varrendo 3.921.495 b
> e a larga foi abortada em 10.600.000 b — exatamente o teto — com
> `"Bytes scanned limit was exceeded"`.

---

**Nota, sobre o critério 4 do `verifica.sh`.** O script testa
`larga == "FAILED"`. O que este Athena (engine v3) devolve no corte por
`BytesScannedCutoffPerQuery` é `CANCELLED`, com
`StateChangeReason = "Bytes scanned limit was exceeded"`. O freio tocou e a estreita
respondeu; o que não bate é o estado que o script procura, e por isso ele imprime
"a consulta estreita nao respondeu" na linha seguinte à sua própria evidência de que ela
respondeu. Não alteramos o script. Evidência bruta em `EVIDENCIA.md`, seção 5.
