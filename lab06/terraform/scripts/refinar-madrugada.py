# refinar-madrugada.py — job Glue da camada refined: Lab-demo 07 (Aula 28) e Exercício 06 (Aula 29).
#
# ENTRADA ....... s3://<bucket>/trusted/corridas/dt=<dia do evento>/*.parquet
#                 a trusted do Ciclo 6: uma linha por corrida, 11 colunas, com o id do passageiro.
# PROCESSAMENTO . só as corridas da madrugada (faixa_hora de 0 a 5), somadas por dia e bairro.
#                 Nenhum id sai daqui: nem corrida, nem motorista, nem passageiro.
#                   --DIAS   todos (refaz a tabela inteira) ou AAAA-MM-DD,AAAA-MM-DD (só esses dias)
# SAIDA ......... s3://<bucket>/refined/madrugada_bairro/dt=<dia>/part-*.parquet
#                 grão: uma linha por bairro e dia. Colunas: bairro, corridas, receita.
#                 + s3://<bucket>/relatorios/madrugada_bairro.json (conferência).
#
# Grava sobrescrevendo só as pastas dt= que este run calcula: rodar de novo dá o mesmo
# resultado (a idempotência da Aula 22, agora na camada de cima).

import json
import sys

import boto3
from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["BUCKET", "DIAS"])
BUCKET, DIAS = args["BUCKET"], args["DIAS"]
ORIGEM = f"s3://{BUCKET}/trusted/corridas/"
DESTINO = f"s3://{BUCKET}/refined/madrugada_bairro/"

sc = SparkContext.getOrCreate()
glue = GlueContext(sc)
spark = glue.spark_session
spark.conf.set("spark.sql.session.timeZone", "UTC")
spark.conf.set("spark.sql.sources.partitionColumnTypeInference.enabled", "false")
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

# 1. LER a trusted (o dt do caminho é o dia do evento).
trusted = spark.read.parquet(ORIGEM)
if DIAS != "todos":
    trusted = trusted.filter(F.col("dt").isin([d.strip() for d in DIAS.split(",")]))

# 2. RESUMIR: madrugada por dia e bairro. Sai a resposta; ficam para trás os ids.
madrugada = trusted.filter(F.col("faixa_hora").between(0, 5))
df = (madrugada.groupBy("dt", "bairro")
      .agg(F.count(F.lit(1)).alias("corridas"),
           F.round(F.sum("valor"), 2).alias("receita"))
      .select("bairro", "corridas", "receita", "dt"))

# 3. ESCREVER, uma pasta por dia, um arquivo por pasta, trocando só as pastas deste run.
df.repartition("dt").write.mode("overwrite").partitionBy("dt").parquet(DESTINO)

# 4. CONFERIR.
tabela = spark.read.parquet(DESTINO)
relatorio = {
    "tabela": "madrugada_bairro", "dias": DIAS,
    "corridas_lidas_da_trusted": trusted.count(),
    "corridas_da_madrugada": madrugada.count(),
    "linhas_gravadas_neste_run": df.count(),
    "dias_gravados_neste_run": df.select("dt").distinct().count(),
    "linhas_na_tabela": tabela.count(),
    "bairros_na_tabela": tabela.select("bairro").distinct().count(),
    "corridas_somadas_na_tabela": tabela.agg(F.sum("corridas")).first()[0],
}
texto = json.dumps(relatorio, indent=2)
print(texto)
boto3.client("s3").put_object(Bucket=BUCKET, Key="relatorios/madrugada_bairro.json",
                              Body=texto.encode("utf-8"), ContentType="application/json")
