# EVIDÊNCIA — Exercício 01: o schema é seu

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Stack `eda-a04-grupo02` · executado em 2026-08-17 · Athena engine v3

---

## 1. A execução, comando a comando

Transcrição da execução final, do `deploy` ao `destroy`. As 30 linhas de `upload` do
`s3 sync` foram omitidas; o resto é literal.

**Subir a stack**

```
$ ./infra/deploy.sh grupo02
regiao us-east-1 · login grupo02 · particoes 2026-08-15 2026-08-16 2026-08-17

Waiting for changeset to be created..
Waiting for stack create/update to complete
Successfully created/updated stack - eda-a04-grupo02

  BucketName      eda-a04-lake-grupo02
  DatabaseName    eda_a04_raw_grupo02
  TableName       corridas
  WorkGroupName   eda-a04-wg-grupo02
  TetoBytes       10600000
```

**Gerar e ingerir os 30 dias**

```
$ python3 app/gerador-eventos.py --dias 30 --taxa 12 --seed 42 --saida "$SAIDA"

objetos ............. 30  (um por partição dt=)
eventos ............. 518.400
bytes ............... 117.655.606
maior partição ...... dt=2026-08-14  3.922.560 bytes
partição de hoje .... dt=2026-08-17  3.921.495 bytes
valor como texto .... 7.688 eventos (1.48%)

$ aws s3 sync "$SAIDA/raw/corridas" "s3://eda-a04-lake-grupo02/raw/corridas/" --region us-east-1
[30 uploads omitidos]
upload: ...\dt=2026-08-17\parte-0001.json
     to s3://eda-a04-lake-grupo02/raw/corridas/dt=2026-08-17/parte-0001.json

$ aws s3 ls "s3://eda-a04-lake-grupo02/raw/corridas/" --recursive --summarize --region us-east-1 | tail -3
Total Objects: 30
   Total Size: 117655606
```

Note o `"$SAIDA/raw/corridas"` no `sync`, e não `"$SAIDA"` — o porquê está na seção 4.

**As quatro consultas** (via helper que roda no workgroup e database da stack)

```
$ ./local/consulta.sh "SELECT bairro, count(*) AS corridas FROM corridas
                       WHERE dt = '2026-08-17' GROUP BY bairro ORDER BY 2 DESC LIMIT 10"
ESTADO : SUCCEEDED
BYTES  : 3921495  (3.74 MB)
RESULTADO: 10 linhas, Boa Viagem 3.055 à frente  → seção 5

$ ./local/consulta.sh "SELECT corrida_id, data_corrida, fim FROM corridas
                       WHERE dt = '2026-08-17' LIMIT 5"
ESTADO : SUCCEEDED
BYTES  : 3921495  (3.74 MB)
RESULTADO:
  c-00501121 | 2026-08-17 00:47:19.000 | 2026-08-17 00:53:13.000
  c-00501122 | 2026-08-17 00:58:21.000 | 2026-08-17 01:01:51.000
  c-00501123 | 2026-08-17 00:26:31.000 | 2026-08-17 00:33:55.000

$ ./local/consulta.sh "SELECT count(*) - count(valor) FROM corridas WHERE dt = '2026-08-17'"
ESTADO : FAILED
BYTES  : 0
MOTIVO : BAD_DATA: Error parsing column 'valor' with value '8,43' ...   → seção 3

$ ./local/consulta.sh "SELECT count(*) FROM corridas"
ESTADO : CANCELLED
BYTES  : 10600000  (10.11 MB)
MOTIVO : Bytes scanned limit was exceeded                               → seção 5
```

A segunda consulta é a evidência da DECISÃO 02: o ISO-8601 com `T` e `Z` foi parseado em
timestamp de verdade, sem nulo. A terceira é a DECISÃO 03 funcionando — a coluna quebrada
recusa a responder em vez de devolver nulo em silêncio.

**Verificar e limpar**

```
$ ./verificacao/verifica.sh grupo02                    → seção 6
$ ./infra/destroy.sh grupo02                           → seção 7
$ ./verificacao/verifica.sh grupo02 --pos-destroy      → seção 7
```

> **Reprodutibilidade.** O lab foi executado duas vezes de ponta a ponta, com `destroy`
> completo entre elas e a stack recriada do zero. Os números saíram idênticos nas duas:
> 117.655.606 bytes gerados, partição de hoje 3.921.495, 7.688 valores como texto
> (1,48%), estreita varrendo 3.921.495 e larga abortada em 10.600.000. É o `--seed 42`
> cumprindo o que promete.

## 2. As medições que sustentam as decisões

| medição | valor |
| --- | --- |
| lake completo no S3 (30 objetos) | 117.655.606 bytes |
| uma partição (`dt=2026-08-17`) | 3.921.495 bytes |
| as 3 partições registradas no catálogo (`dt=2026-08-15/16/17`) | 11.765.273 bytes |
| teto declarado (`TetoBytesPorConsulta`) | 10.600.000 bytes |
| linhas na partição de hoje | 17.280 |
| linhas com `valor` fora do tipo declarado (DECISÃO 01) | 245 — 1,42% |
| `sum(valor)` do dia, **se** os 245 virarem nulo | 298.049,18 (≈ R$ 4,3 mil a menos) |

As duas últimas foram medidas com `use.null.for.invalid.data = true`. Na configuração
final (`false`), essas 245 linhas fazem a consulta falhar em vez de sumir — ver seção 3.

```
$ aws s3 ls s3://eda-a04-lake-grupo02/raw/corridas/ --recursive --summarize
Total Objects: 30
   Total Size: 117655606

$ aws s3 ls .../dt=2026-08-15/ --summarize   Total Size: 3921456
$ aws s3 ls .../dt=2026-08-16/ --summarize   Total Size: 3922322
$ aws s3 ls .../dt=2026-08-17/ --summarize   Total Size: 3921495
                                             soma:      11765273
```

O número que decide o teto é o **11.765.273**, não o 117.655.606: com 3 partições
registradas, é tudo o que o catálogo expõe a uma consulta.

## 3. O experimento da DECISÃO 03 (três deploys)

Cada linha é uma stack realmente subida e consultada, não uma suposição:

| `ignore.malformed.json` | `use.null.for.invalid.data` | `count(*)` / painel de bairros | consulta que lê `valor` |
| --- | --- | --- | --- |
| `true` | `true` | SUCCEEDED · 3.921.495 b | SUCCEEDED — 245 nulos |
| `false` | `true` | SUCCEEDED · 3.921.495 b | SUCCEEDED — 245 nulos (**idêntico**) |
| `false` | `false` | **SUCCEEDED** | **FAILED** |

Conclusões medidas:

1. **`ignore.malformed.json` é inerte neste dado.** Ele governa a *linha* que não é JSON
   válido, e o dataset não tem nenhuma. `"8,43"` é JSON válido com valor inválido.
2. **Quem decide barulho x silêncio é `use.null.for.invalid.data`.**
3. **A falha é por coluna, não por consulta.** Com ambas em `false`, `SELECT count(*)` e
   o painel de bairros seguiram respondendo — inclusive as consultas que o `verifica.sh`
   usa no critério 4.

Mensagem completa do erro na configuração escolhida:

```
BAD_DATA: Error parsing column 'valor' with value '8,43' with error:
'io.trino.spi.TrinoException: Error Parsing a column in the table: Character , is
neither a decimal digit number, decimal point, nor "e" notation exponential mark.'.
Please remove or correct the data in this file:
s3://eda-a04-lake-grupo02/raw/corridas/dt=2026-08-17/parte-0001.json.
To treat invalid data as null to avoid this error, add the table property
'use.null.for.invalid.data' = 'true' to the table containing the invalid data.
```

Ela nomeia arquivo, coluna, valor ofensor e a correção. É um chamado com endereço, não
um erro críptico.

## 4. O comando de ingestão do enunciado (verificado com `--dryrun`)

O enunciado manda `aws s3 sync ./saida "s3://$BUCKET/raw/corridas/"`, mas o gerador já
grava em `./saida/raw/corridas/dt=…`. Rodado em `--dryrun`, sem subir nada:

```
(dryrun) upload: ...\saida\raw\corridas\dt=2026-07-19\parte-0001.json
      to s3://eda-a04-lake-grupo02/raw/corridas/raw/corridas/dt=2026-07-19/parte-0001.json
```

O prefixo sai duplicado: `raw/corridas/raw/corridas/dt=…`. O `Location` das partições
apontaria para um prefixo vazio e o Athena devolveria **zero linha sem erro nenhum** —
o item 2 da lista "o que mais reprova" do enunciado, derrubando os critérios 3 e 4.

Comando usado na ingestão real:
`aws s3 sync ./saida/raw/corridas "s3://$BUCKET/raw/corridas/"`

## 5. A prova do custo da consulta (critério 4)

**Estreita — precisa responder:**

```sql
SELECT bairro, count(*) AS corridas FROM corridas
WHERE dt = '2026-08-17' GROUP BY bairro ORDER BY 2 DESC LIMIT 10;
```
```
ESTADO : SUCCEEDED
BYTES  : 3921495
Boa Viagem 3055 · Pina 1340 · Recife Antigo 1028 · Ilha do Leite 945 · Espinheiro 853
Graças 837 · Madalena 822 · Casa Forte 781 · Torre 720 · Boa Vista 712
```

**Larga — precisa morrer no teto:**

```sql
SELECT count(*) FROM corridas;
```
```json
{
    "SQL": "SELECT count(*) FROM corridas",
    "Estado": "CANCELLED",
    "Motivo": "Bytes scanned limit was exceeded",
    "Bytes": 10600000
}
```

O `DataScannedInBytes` da larga é **exatamente o teto** — 10.600.000 — porque é o ponto
em que o Athena desistiu. A estreita leu 3.921.495 e respondeu. O freio tocou.

### Nota: `CANCELLED` vs `FAILED` no critério 4

O `verifica.sh` decide o critério 4 assim:

```bash
if [[ "${larga%%|*}" == "FAILED" && "${estreita%%|*}" == "SUCCEEDED" ]]; then
```

Medido nesta conta, no Athena engine v3: o corte por `BytesScannedCutoffPerQuery`
devolve **`CANCELLED`**, com `StateChangeReason = "Bytes scanned limit was exceeded"`.
Não sabemos dizer o que o script esperava encontrar quando foi escrito — só que o estado
que este motor produz não é `FAILED`.

Vale notar que o script **enxerga** o `CANCELLED`: o `case` da linha 170
(`SUCCEEDED|FAILED|CANCELLED`) o aceita como estado terminal, encerra o laço de espera e
o imprime na linha de `info`. O que não o considera é o julgamento da linha 187, que
compara com um valor só.

Com `larga=CANCELLED` e `estreita=SUCCEEDED`, o `if` cai no `else` da linha 191 e o
script imprime *"a consulta estreita nao respondeu"* na linha imediatamente abaixo da
sua própria evidência de que ela respondeu (`SUCCEEDED · 3921495 bytes`). Esse `else`
atende a qualquer estado da larga que não seja `FAILED` nem `SUCCEEDED` — `CANCELLED`,
`TIMEOUT`, `ERRO` — e atribui a falha à consulta estreita, cujo estado ele não examina
naquele ramo.

O script não foi alterado — a saída da seção 6 é a que ele realmente produziu. O
comportamento exigido pela rubrica ("o teto mata a consulta larga e deixa passar a
estreita") está demonstrado no JSON acima.

## 6. Saída do `verifica.sh` (antes do destroy)

```
verificacao do Exercicio 01 · login grupo02 · regiao us-east-1

CRITERIO 0 - sem Crawler (elimina)
  [PASSA]   nenhum Crawler, e ha AWS::Glue::Table

CRITERIO 1 - os cinco outputs de contrato (10%)
            BucketName = eda-a04-lake-grupo02
            DatabaseName = eda_a04_raw_grupo02
            TableName = corridas
            WorkGroupName = eda-a04-wg-grupo02
            TetoBytes = 10600000
  [PASSA]   os cinco existem e estao preenchidos

CRITERIO 2 - schema declarado (25%)
            colunas declaradas: 9
            chave de particao: dt
  [PASSA]   ≥ 8 colunas e chave de particao dt
            valor foi declarado como: decimal(10,2)  (DECISAO 01 - justifique)

CRITERIO 3 - particoes declaradas (15%)
            particoes registradas: 3
            a particao de hoje (2026-08-17) esta declarada: sim
  [PASSA]   ≥ 3 particoes, e a de hoje esta entre elas
  [PASSA]   todo Location bate com a chave dt= do objeto

CRITERIO 4 - o teto mata a larga e deixa passar a estreita (15%)
            consulta larga   (sem WHERE dt): CANCELLED · 10600000 bytes
            consulta estreita (com WHERE dt): SUCCEEDED · 3921495 bytes
            teto declarado: 10600000 bytes
  [FALHA]   a consulta estreita nao respondeu - confira Location e particoes

CRITERIO 6 - DECISOES.md (20%)
            decisoes encontradas no arquivo: 5 de 5
  [PASSA]   as cinco decisoes aparecem (o texto e lido por uma pessoa)

resumo: 1 criterio(s) em FALHA
```

## 7. Limpeza e `verifica.sh --pos-destroy` (critério 5)

```
$ ./infra/destroy.sh grupo02

esvaziando s3://eda-a04-lake-grupo02
apagando a stack eda-a04-grupo02

conferencia:
  [limpo]    stack
  [limpo]    bucket
  [limpo]    database
  [limpo]    tabela
  [limpo]    workgroup

conta limpa: nenhum recurso desta stack sobrou.
```

```
$ ./verificacao/verifica.sh grupo02 --pos-destroy

verificacao do Exercicio 01 · login grupo02 · regiao us-east-1

CRITERIO 5 - destroy limpo (15%)
  [PASSA]   nenhum recurso orfao

----- cole no PR a partir daqui -----
[PASSA]   nenhum recurso orfao
-------------------------------------
```

Conferido também por varredura direta na conta, sem passar pelos scripts:

```
stack eda-a04-grupo02 .......... DELETE_COMPLETE
bucket eda-a04-lake-grupo02 .... inexistente
database eda_a04_raw_grupo02 ... inexistente
workgroup eda-a04-wg-grupo02 ... inexistente
```

Nada cobra por hora ligada neste template, e sem bucket não há armazenamento: a conta
para em zero.

---

> **Nota sobre o ambiente.** Os scripts do pacote chamam `python3`, convenção de
> Linux/macOS. Neste computador (Windows + Git Bash) esse nome resolve para o stub da
> Microsoft Store, e os caminhos POSIX que o `deploy.sh` embute dentro de `python3 -c`
> não são abertos pelo Python do Windows. Contornamos com um shim local, fora da
> entrega; nenhum script foi modificado.
