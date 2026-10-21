# DECISOES.md · Exercício 04: a meta de custo, em Parquet particionado

**Grupo 02** · Turma 2026-2 · sufixo `grupo02` · região `us-east-1`
Conta `325583868777` · executado em 2026-10-21 · Terraform v1.15.8 · provider AWS 5.100.0
Bucket `eda-a21-lake-grupo02` · database `eda_a21_grupo02` · tabela `trusted_corridas` ·
workgroup `eda-a21-wg-grupo02`

Cada decisão vem acompanhada do número que a sustenta, medido nesta conta. A
referência é sempre a pergunta da madrugada de 7 dias (`dt >= '2026-10-15'` e
`faixa_hora` entre 0 e 5), que devolveu 22 bairros e 11.137 corridas em todas as
medições descritas aqui. Para a DECISÃO 01, construímos e medimos de fato o
layout alternativo, em vez de apenas estimá-lo. A evidência bruta, comando a comando,
está em `EVIDENCIA.md`.

Os valores das quatro variáveis de decisão, já que o `terraform.tfvars` não é
versionado por exigência da rubrica:

```
chaves_particao      = ["dt"]
arquivos_por_pasta   = 1
meta_bytes_madrugada = 524288
teto_bytes           = 10485760
```

---

## DECISÃO 01: a chave de partição é `["dt"]`

Particionamos a trusted apenas por data. A alternativa `["dt", "bairro"]` parece
convidativa, porque a pergunta agrupa por bairro, mas ela pede todos os bairros: a
partição por bairro não descarta pasta nenhuma, apenas multiplica por 22 o número de
arquivos que a consulta precisa abrir. Em vez de apoiar a escolha na estimativa da
seção 6 do roteiro do Lab 05, construímos os dois layouts sobre o mesmo dado e os
consultamos da mesma forma. Com `dt`, a semana abre 7 arquivos e lê 355.803 bytes; com
`dt` e `bairro`, abre 154 arquivos e lê 613.639 bytes, 72% a mais pela mesma resposta.
Aceitamos, em troca, que uma consulta restrita a um único bairro leia o dia inteiro de
cada data, quando no layout por bairro leria apenas a fatia daquele bairro.

> **Medido.**
>
> ```
>                                    ["dt"]          ["dt", "bairro"]
> pastas em 30 dias                  30              660
> arquivos abertos pela pergunta     7               154
> Data scanned da pergunta           355.803 B       613.639 B
> consulta larga do critério 5       17.727.527 B    22.530.409 B
> trusted inteira                    18.143.089 B    24.115.255 B
> resposta                           22 / 11.137     22 / 11.137
> ```
>
> A diferença não está no dado. Particionar por bairro dispensa a leitura da coluna
> `bairro`, mas, com apenas 22 valores distintos, ela quase nada pesa depois de
> comprimida: o dado efetivamente lido ficou em 341.201 bytes no layout por data e em
> 326.791 bytes no layout por bairro. Toda a diferença está nos rodapés, tema da
> decisão seguinte.

## DECISÃO 02: um arquivo por pasta

Cada pasta de dia recebeu um único arquivo. Um dia inteiro ocupa cerca de 590 KB em
Parquet, muito abaixo do tamanho em que dividir o arquivo traria algum ganho de
paralelismo, e cada arquivo adicional representa mais um rodapé que o motor precisa
ler antes de qualquer coluna, além de mais um pedido ao S3. O rodapé foi medido
diretamente, a partir dos 8 últimos bytes de cada arquivo, onde o formato Parquet
registra o comprimento do rodapé seguido da marca `PAR1`. No layout final, cada
arquivo carrega 2.078 bytes de rodapé, e a pergunta de 7 dias lê 14.602 bytes deles,
4% da leitura total. No layout picado medido para a decisão anterior, com arquivos de
35,7 KB em média, os rodapés somaram 286.848 bytes, 47% de tudo o que a consulta leu: o
comportamento que o roteiro do Lab 05 resume como "metade é rodapé" se confirmou com
medição própria. Aceita-se abrir mão do paralelismo de leitura dentro de um mesmo dia,
irrelevante neste volume.

> **Medido.**
>
> ```
> arquivos por pasta                   1
> tamanho de cada arquivo              589,6 a 591,7 KB (média 590,6 KB)
> rodapé de cada arquivo               2.078 B
> rodapés lidos pela pergunta          14.602 B = 7 × (2.078 + 8)       4% da leitura
> no layout picado (154 arquivos)      286.848 B                        47% da leitura
> ```

## DECISÃO 03: a meta de custo é 524.288 bytes (512 KiB)

Qualquer valor entre os 355.803 bytes medidos e 1 MiB cumpriria o requisito; o que
define o número é o papel que a meta deve desempenhar. Optamos por um valor que
funcione como alarme. Ele deixa 47% de folga sobre a leitura atual, para que o
crescimento natural do volume não quebre a promessa no dia seguinte, e ao mesmo tempo
reprova os dois erros que foram efetivamente medidos: a partição por bairro, que lê
613.639 bytes, e o filtro pela coluna de dentro do arquivo, `date(inicio)`, no lugar
da chave do caminho, que lê 4.472.250 bytes para chegar exatamente à mesma resposta.
Uma meta de 1 MiB aceitaria o layout picado e deixaria de distinguir o desenho correto
do desperdício. Aceita-se que a meta precise ser revista quando o volume diário
crescer em torno da metade.

> **Medido.**
>
> ```
> meta                                              524.288 B
> pergunta da madrugada, layout final               355.803 B   dentro da meta   11.137 corridas
> a mesma pergunta, partição dt + bairro            613.639 B   acima da meta    11.137 corridas
> a mesma pergunta, WHERE date(inicio) >= ...     4.472.250 B   acima da meta    11.137 corridas
> ```
>
> O filtro por `date(inicio)` é o erro que não dá erro: a resposta sai certa, mas, como
> a data não está no caminho, o Athena não tem como podar pastas e abre os 30 arquivos,
> lendo 12,6 vezes mais.

## DECISÃO 04: o teto do workgroup é 10.485.760 bytes (10 MiB)

Adotamos como teto o menor valor que o Athena aceita, com `enforce` ligado para valer a
qualquer cliente que consulte pelo workgroup. Medimos a fronteira com a mesma consulta
de todas as colunas usada no critério 5: o teto deixa passar até 17 dias completos e
barra a partir do 18º, bem como a varredura do mês inteiro, de 17.727.527 bytes; a
pergunta da madrugada consome apenas 3,4% dele. Além da contenção, há um argumento de
custo: como o Athena cobra no mínimo 10 MB por consulta, conforme o roteiro do Lab 05,
um teto nesse patamar faz com que nenhuma consulta deste workgroup custe, na prática,
mais do que a cobrança mínima. O preço é que uma extração de todas as colunas do mês
inteiro não roda aqui: precisa ser dividida por intervalo de datas ou executada em
outro workgroup. Um teto logo abaixo da varredura completa, em torno de 16 MiB, foi
descartado por deixar menos de 1 MB de margem e por não haver critério que justifique
liberar 28 dias e barrar 30.

> **Medido.**
>
> ```
> todas as colunas, 17 dias    SUCCEEDED    10.045.467 B
> todas as colunas, 18 dias    CANCELLED    10.485.760 B    Bytes scanned limit was exceeded
> todas as colunas, 30 dias    CANCELLED    10.485.760 B    Bytes scanned limit was exceeded
> pergunta da madrugada        SUCCEEDED       355.803 B
> ```
>
> As consultas barradas param exatamente no teto: o Athena interrompe a leitura ao
> atingir o corte, e cobra apenas o que leu até ali.

## DECISÃO 05: o registro das partições é feito por partition projection

As partições não são registradas no catálogo: a regra declara `dt` como data diária
de 2026-01-01 até `NOW`, e o Athena calcula as pastas a partir dela. A motivação vem da
própria pergunta, que olha os últimos 7 dias e roda diariamente, de modo que todo dia
chega uma pasta nova. Com `MSCK REPAIR TABLE`, cada dia novo exige um passo manual, e o
esquecimento não produz erro, produz um número errado. Demonstramos isso antes da
troca: ao remover do catálogo apenas a partição do dia corrente, com o arquivo intacto
no S3, a pergunta respondeu 9.546 corridas em vez de 11.137, com estado `SUCCEEDED`. A
leitura também caiu, para 237.902 bytes, de forma que a meta de custo continuaria
cumprida com a resposta errada, o que explica por que a verificação exige, além da
leitura, a contagem exata. No dia 31, com a projeção, a pasta nova passa a ser
encontrada assim que a data chega, sem ação nenhuma. O início fixo é deliberado: uma
janela móvel, como "os últimos 30 dias", esconderia a cada dia a data mais antiga,
também sem erro. Aceitamos que apenas o Athena enxergue as partições, já que outra
ferramenta lendo pelo catálogo não encontraria nenhuma, e que o catálogo deixe de
documentar quais dias de fato existem.

> **Medido.**
>
> ```
>                                  partições    corridas / dias    madrugada    estado
> MSCK, catálogo completo          30           518.400 / 30       11.137       SUCCEEDED
> MSCK, sem a partição de hoje     29           501.120 / 29        9.546       SUCCEEDED
> projeção, catálogo vazio          0           518.400 / 30       11.137       SUCCEEDED
> ```
>
> Com a projeção e nenhuma partição registrada, a pergunta leu os mesmos 355.803 bytes
> do layout registrado por MSCK: a projeção muda como as pastas são encontradas, não
> quanto se lê.

---

## Observações sobre a execução

**O bucket do estado remoto.** O `backend.hcl.example` fornecido no pacote traz
`bucket = "eda-tfstate-CONTA"`, e no roteiro do Lab 05 `CONTA` é o número da conta AWS.
O enunciado, porém, descreve o cenário como execução "na conta do grupo", e a turma
compartilha uma única conta. Como não existe bucket de estado com o número da conta, e
os grupos que dividem a conta mantêm cada um o seu próprio bucket, reaproveitou-se o
`eda-tfstate-grupo02`, criado no Exercício 03 fora do Terraform para sobreviver aos
`destroy`. O que é inequívoco no exemplo foi seguido literalmente: a chave
`aula21/grupo-02/terraform.tfstate` e a tabela de trava `eda-tflock`.

**A troca de layout entre as duas medições.** Mudar `chaves_particao` é uma
atualização no lugar para o Terraform, o que deixaria no catálogo as 660 partições de
dois níveis do layout por bairro. Entre as medições, a tabela foi recriada com
`terraform apply -replace=aws_glue_catalog_table.trusted`, e o mesmo foi feito ao
adotar a projeção, para que o catálogo começasse vazio e ficasse provado que quem
encontra as pastas é a regra.
