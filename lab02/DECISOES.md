# DECISOES.md — Exercício 02: do zero em Terraform

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Bucket `eda-a08-lake-grupo02` · database `eda_a08_lake_grupo02` · workgroup
`eda-a08-wg-grupo02` · executado em 2026-09-01 · Terraform v1.15.8 · Athena engine v3

Uma frase por decisão, e sob ela a medição que a sustenta. Todos os números saíram
desta conta; onde a medição contrariou o que supúnhamos, está dito. A evidência
bruta, comando a comando, está em `EVIDENCIA.md`.

---

## DECISÃO 01 — o tipo de `valor`: `decimal(10,2)`

Declaramos `decimal(10,2)` porque preço de corrida é contrato de dois centavos e
binary float não guarda dinheiro, e **aceitamos perder a disponibilidade da coluna**:
com as duas chaves do SerDe em `false` (DECISÃO 03), um `valor` que não couber no
tipo derruba a consulta em vez de virar `null`, e enquanto a origem não for corrigida
ninguém lê `valor`. Preferimos isso a `double`, que converteria sozinho e apagaria o
problema em silêncio, e a `string`, que não perde nada hoje mas cobra um
`cast(replace(valor,',','.') as double)` de toda consulta escrita daqui em diante —
e alguém vai esquecer, longe de quem poderia consertar a origem.

> **Medido:** as 128.000 linhas dos 8 dias chegam com `valor` como número JSON —
> `{'float': 128000}`, faixa `6.5` a `58.0`. **Zero** com vírgula decimal, zero como
> texto. O enunciado afirma que ~1,5% mandam `"17,82"`; **neste gerador isso não
> acontece**, e declaramos o tipo para o dado prometido, não só para o de hoje. Com o
> tipo no ar, `SELECT count(valor)` devolveu 16.000 de 16.000 sem um nulo,
> `sum(valor)` = 517.959,19, mínimo `6.50` e máximo `58.00` — com o zero final
> preservado, que é comportamento de `decimal` e não de binary float.

## DECISÃO 02 — o tipo das colunas de tempo: `string`

Ficamos com `string` porque **testamos e `timestamp` não lê este dado**, e
**aceitamos perder a aritmética temporal nativa**: sem `date_diff` e sem `hour()`,
todo recorte de horário sai de comparação e `substr` sobre texto. Não é preferência
de estilo — é o único tipo que devolve o valor que está no arquivo.

> **Medido:** os campos chegam como `"02:31:00"` — hora do dia, **sem data** — em
> 128.000 de 128.000 linhas. Com a tabela no ar,
> `count(try_cast(data_corrida AS timestamp))` devolveu **0 de 16.000**: declarar
> `timestamp` teria nulado a coluna inteira, em silêncio, porque o Athena espera
> `AAAA-MM-DD HH:MM:SS`. A amostra confirma o formato:
> `c20260901000000 | 02:31:00 | 02:54:00 | 19.49`.
>
> **Achado que não procurávamos:** em **50.148 das 128.000 linhas (39,18%)** o `fim`
> é anterior ao `data_corrida` — o gerador soma os minutos sem carregar a hora, então
> uma corrida que começa `22:41` e dura 33 min termina `22:14`. `string` não pega
> isso, mas `timestamp` também não pegaria: o defeito é de conteúdo, não de tipo.
> Declaramos como dívida de qualidade conhecida, para a Aula 26 medir.

## DECISÃO 03 — o SerDe: `ignore.malformed.json` **e** `use.null.for.invalid.data`, ambas em `false`

Escolhemos **barulho**, e **aceitamos perder a disponibilidade da consulta** no dia
em que a origem degradar: uma linha ruim para o painel inteiro em vez de sub-reportar
o número. Quem paga é quem consulta, no minuto em que o dado quebra — e não ninguém,
que é quem paga no silêncio. Declaramos as duas chaves porque **elas cobrem defeitos
diferentes**: `ignore.malformed.json` trata a *linha* que não é JSON válido, e
`use.null.for.invalid.data` trata a linha válida cujo *valor* não cabe no tipo. O
`"17,82"` que o enunciado cita é do segundo caso — declarar só a primeira deixaria
exatamente o caso citado descoberto.

> **Medido:** neste dado as duas chaves são **inertes, e comprovadamente**: 0 linhas
> malformadas e 0 valores fora do tipo em 128.000. `true` e `false` produzem
> resultado idêntico aqui, porque não existe nenhuma linha que os diferencie. A
> escolha não conserta uma falha atual — ela decide o comportamento do dia em que a
> sujeira chegar.
>
> **Onde as declaramos importa mais que o valor.** O andaime traz a chave só em
> `parameters` da tabela, e o bloco `ser_de_info` da partição vem **sem `parameters`
> nenhum**. Como toda consulta desta tabela é sobre partição registrada, o SerDe que
> vale é o da partição — foi o que medimos no lab01. Declaramos as duas chaves nos
> **três** lugares: `parameters` da tabela, `ser_de_info` da tabela e `ser_de_info` de
> cada partição. Sem o terceiro, a decisão não seria lida por consulta nenhuma.

## DECISÃO 04 — quantas partições: **as 8 que subimos**, incluindo a de hoje

Registramos os 8 dias porque o catálogo existe para descrever o lake, e
**aceitamos a dívida operacional de que o catálogo não se atualiza sozinho**: o dado
que chegar amanhã, dia 2, não aparece até alguém rodar `aws glue create-partition`,
um `MSCK REPAIR`, ou reaplicar o Terraform com a data nova na lista. Registrar menos
que o que subimos seria expor uma tabela que responde um número menor que a verdade,
sem erro nenhum — e não havia restrição que nos obrigasse: o `for_each` sobre
`var.dias_particao` aceita qualquer tamanho de lista, diferente do lab01, onde o
CloudFormation limitava a três parâmetros.

> **Medido, e é a medição que mais nos ensinou.** Entre o `apply` (que registra as
> partições) e o upload (que põe o dado lá) existe uma janela em que as 8 partições
> apontam para pastas vazias. Medimos nela:
>
> ```
> objetos no bucket ......... 0
> partições registradas ..... 8
> SELECT count(*) FROM corridas
>   ESTADO : SUCCEEDED        <- teve SUCESSO
>   BYTES  : 0
>   total  : 0                <- zero, com toda a confiança do mundo
> ```
>
> Nenhum erro, nenhum aviso. Catálogo e dado são independentes, e quando discordam
> quem responde é o catálogo, em silêncio. Depois do upload a mesma consulta devolveu
> `128.000` varrendo `27.268.865` bytes — idêntico ao `Total Size` do S3.
>
> **Por que não o mínimo da rubrica.** Três partições varrem 10.225.855 bytes, e o
> menor teto que o Athena aceita é 10.485.760: a consulta larga varreria **259.905
> bytes a menos** que o menor freio possível. Com 3 partições o critério 4 não é
> difícil — é **aritmeticamente impossível**. O mínimo da rubrica não fecha com o
> volume que este gerador produz.

## DECISÃO 05 — o teto de bytes por consulta: `15.728.640` (15 MiB)

O número saiu da medição das partições nesta conta e declara uma **política**: uma
consulta legítima nomeia poucos dias, e a tabela é particionada por `dt` exatamente
para isso. Até 4 dias passa — o comparativo de "hoje contra os três anteriores" —, e
do 5º em diante quem pergunta está varrendo o lake e precisa assumir isso. **Aceitamos
perder a consulta de janela larga sem aviso prévio**: quem precisar de uma semana
inteira vai receber um corte, e não um resultado lento e caro.

> **Medido:** uma partição 3.408.870 b · as 8 registradas 27.268.865 b · piso da AWS
> 10.485.760 b. Com o teto no ar, as quatro consultas:
>
> ```
> larga     8 dias   CANCELLED   15.728.640   Bytes scanned limit was exceeded
> estreita  1 dia    SUCCEEDED    3.408.870   total = 16.000
> controle  4 dias   SUCCEEDED   13.634.989   total = 64.000
> controle  5 dias   CANCELLED   15.728.640   Bytes scanned limit was exceeded
> ```
>
> A política declarada e a política observada são a mesma. O Athena **para de varrer
> ao atingir o corte**: por isso os dois casos barrados reportam 15.728.640, e não os
> 27,3 MB ou 17,0 MB que teriam varrido.
>
> **Não é o piso** (10.485.760) porque ele barraria uma consulta de 4 dias, e uma de 3
> dias varre 10.225.855 — apenas 259.905 bytes abaixo dele. No piso, uma janela de 3
> dias já opera na beirada, e qualquer crescimento no volume diário passa a barrar
> consulta legítima: é um freio que quebra sozinho quando o dado cresce.
>
> **Não é o topo** (117.455.962) porque ele é **4,3× o lake inteiro**. Freio acima da
> consulta mais pesada que existe nunca toca — é decorativo, como os 10 GiB que o Lab
> 01 nunca tocou. E mesmo 27.268.865 exato estaria errado: o freio tem que ficar
> abaixo do que ele deve impedir.
>
> **A folga não é enfeite.** A consulta de 4 dias varreu 13.634.989 bytes, **1.113 a
> mais** que a soma dos arquivos (13.633.876). Um teto colado na fronteira teria
> barrado justamente o que pretendia liberar.

---

## Duas observações sobre a execução

**Sobre o critério 4 do `verifica.sh`.** O script exige `estado == "FAILED"`. O que
este Athena devolve no corte por `BytesScannedCutoffPerQuery` é **`CANCELLED`**, com
`StateChangeReason = "Bytes scanned limit was exceeded"`. As duas condições do teste
são `[ "$lest" = "FAILED" ] && [ "$larga_morreu" = "sim" ]`: a segunda casa, a
primeira não. Por isso ele imprime `larga_barrada=0` na linha seguinte à sua própria
evidência de que o freio disparou. O requisito do enunciado — o teto mata a larga e
deixa passar a estreita — está atendido e medido. **Não alteramos o script:** a saída
dele é o aceite, e adulterar o verificador para ganhar ponto seria trocar a medição
pelo resultado dela. É a mesma observação que registramos no lab01.

**Sobre o `main.tf` do andaime.** O arquivo distribuído não compila: os 18 blocos
`columns { name = ... type = ... }` põem dois argumentos num bloco de uma linha, o que
o HCL2 não aceita. Confirmamos que o defeito vem do pacote, e não de edição nossa,
rodando o `terraform fmt` no arquivo original intocado — mesmo erro — e expandindo um
único bloco, quando o erro andou para o seguinte. A correção é sintática, é a forma
que o `terraform fmt` gera, e não muda nenhuma coluna, nome ou tipo. Detalhamento em
`EVIDENCIA.md`.
