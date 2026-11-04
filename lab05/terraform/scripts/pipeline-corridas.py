# pipeline-corridas.py — job Glue do Lab-demo 06 (Aula 24) e do Exercício 05 (Aula 25).
#
# ENTRADA ....... s3://<bucket>/raw/corridas/dt=<dia de CHEGADA>/*.json
#                 o cru do Lab 04; na raw, dt é o dia em que o arquivo chegou.
# PROCESSAMENTO . limpa e tipa como no Lab 05, calcula o dia do EVENTO de cada
#                 corrida e escolhe o que gravar com quatro argumentos:
#                   --MODO     append       acrescenta arquivos (rodar de novo duplica)
#                              sobrescrever troca as partições que o job escreve
#                   --JANELA   na carga diária (DIAS=todos), quantos dias depois do
#                              evento uma corrida ainda é aceita (0 = só o próprio dia)
#                   --DIAS     todos (a carga diária), ou uma lista AAAA-MM-DD,AAAA-MM-DD
#                              de dias do evento: o backfill, que refaz esses dias
#                              inteiros com qualquer atraso (a janela não se aplica)
#                   --CHAVE    corrida_id (uma linha por corrida) ou nenhuma
# SAIDA ......... s3://<bucket>/trusted/<TABELA>/dt=<dia do EVENTO>/part-*.parquet
#                 + s3://<bucket>/relatorios/<TABELA>.json (conferência).
#
# A tabela é declarada no template (Lab 06) ou no Terraform (Exercício 05), com
# partition projection: o job não precisa registrar partição nenhuma.

import json
import sys

import boto3
from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import Window
from pyspark.sql import functions as F
from pyspark.sql import types as T

args = getResolvedOptions(sys.argv, ["BUCKET", "TABELA", "MODO", "JANELA", "DIAS", "CHAVE"])
BUCKET, TABELA, MODO = args["BUCKET"], args["TABELA"], args["MODO"]
JANELA, DIAS, CHAVE = int(args["JANELA"]), args["DIAS"], args["CHAVE"]
if MODO not in ("append", "sobrescrever"):
    raise ValueError("--MODO precisa ser append ou sobrescrever")
ORIGEM = f"s3://{BUCKET}/raw/corridas/"
DESTINO = f"s3://{BUCKET}/trusted/{TABELA}/"

sc = SparkContext.getOrCreate()
glue = GlueContext(sc)
spark = glue.spark_session
spark.conf.set("spark.sql.session.timeZone", "UTC")
spark.conf.set("spark.sql.sources.partitionColumnTypeInference.enabled", "false")
# sobrescrever = trocar SÓ as partições que este run escreve, e não a tabela inteira
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

# 1. LER a raw inteira; o dt do caminho é o dia de CHEGADA do arquivo.
SCHEMA_RAW = T.StructType([
    T.StructField("corrida_id", T.StringType()),
    T.StructField("motorista_id", T.StringType()),
    T.StructField("passageiro_id", T.StringType()),
    T.StructField("bairro", T.StringType()),
    T.StructField("data_corrida", T.StringType()),
    T.StructField("fim", T.StringType()),
    T.StructField("distancia_km", T.DoubleType()),
    T.StructField("duracao_min", T.DoubleType()),
    T.StructField("valor", T.StringType()),
])
raw = spark.read.schema(SCHEMA_RAW).json(ORIGEM)

# 2. TRANSFORMAR como no Lab 05, mais duas colunas: o dia do evento e o de chegada.
inicio = F.to_timestamp(F.col("data_corrida"))
df = raw.select(
    "corrida_id", "motorista_id", "passageiro_id", "bairro",
    inicio.alias("inicio"),
    F.to_timestamp(F.col("fim")).alias("fim"),
    "distancia_km", "duracao_min",
    F.regexp_replace(F.col("valor"), ",", ".").cast("double").alias("valor"),
    F.hour(inicio).alias("faixa_hora"),
    F.col("dt").alias("chegada"),
    F.date_format(inicio, "yyyy-MM-dd").alias("dt"),
)
lidas = df.count()

# 3. ESCOLHER. Carga diária (DIAS=todos): só o que chegou dentro da janela, e o
#    resto é contado em fora_da_janela. Backfill (DIAS=dias do evento): esses dias
#    inteiros, chegados com qualquer atraso; é para isso que o backfill existe.
atraso = F.datediff(F.to_date("chegada"), F.to_date("dt"))
if DIAS == "todos":
    fora = df.filter(atraso > JANELA).count()
    df = df.filter((atraso >= 0) & (atraso <= JANELA))
else:
    df = df.filter(F.col("dt").isin([d.strip() for d in DIAS.split(",")]))
    fora = 0
    df = df.filter(atraso >= 0)

# 4. A CHAVE: uma linha por corrida. Se a mesma corrida chegou duas vezes,
#    fica a primeira chegada.
antes = df.count()
if CHAVE != "nenhuma":
    w = Window.partitionBy(CHAVE).orderBy("chegada")
    df = df.withColumn("_n", F.row_number().over(w)).filter("_n = 1").drop("_n")
depois = df.count()

# 5. ESCREVER, uma pasta por dia do evento, um arquivo por pasta.
modo = "append" if MODO == "append" else "overwrite"
df.repartition("dt").write.mode(modo).partitionBy("dt").parquet(DESTINO)

# 6. CONFERIR: o que este run gravou, e o que a tabela tem depois dele.
tabela = spark.read.parquet(DESTINO)
relatorio = {
    "tabela": TABELA, "modo": MODO, "janela": JANELA, "dias": DIAS, "chave": CHAVE,
    "linhas_lidas_da_raw": lidas,
    "fora_da_janela": fora,
    "duplicatas_removidas": antes - depois,
    "linhas_gravadas_neste_run": depois,
    "dias_gravados_neste_run": df.select("dt").distinct().count(),
    "linhas_na_tabela": tabela.count(),
    "corridas_distintas_na_tabela": tabela.select("corrida_id").distinct().count(),
}
texto = json.dumps(relatorio, indent=2)
print(texto)
boto3.client("s3").put_object(Bucket=BUCKET, Key=f"relatorios/{TABELA}.json",
                              Body=texto.encode("utf-8"), ContentType="application/json")
