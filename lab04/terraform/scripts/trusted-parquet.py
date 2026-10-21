# trusted-parquet.py — job Glue do Exercício 04 (Aula 21).
#
# ENTRADA ....... s3://<bucket>/raw/corridas/dt=AAAA-MM-DD/*.json
#                 o mesmo JSON cru dos Labs 04 e 05: 9 campos, ~1,5% dos `valor` como "17,82".
# PROCESSAMENTO . le a raw com o schema declarado, limpa e tipa (como no Lab 05) e
#                 grava a trusted UMA vez, em Parquet + Snappy, com o layout que o
#                 grupo decidiu: a chave de particao (DECISAO 01) e quantos arquivos
#                 por pasta (DECISAO 02). As duas chegam como argumentos do job,
#                 declarados no Terraform: o layout fica no codigo da infraestrutura.
# SAIDA ......... s3://<bucket>/trusted/corridas/<chave>=<valor>/.../part-*.snappy.parquet
#                 + s3://<bucket>/relatorios/trusted-parquet.json (conferencia).
#
# A tabela NAO e criada aqui: esta declarada no Terraform (aws_glue_catalog_table).
# O job so grava os arquivos. Rodar de novo nao duplica (mode overwrite).

import json
import sys

from pyspark.sql import functions as F
from pyspark.sql import types as T

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


def transformar(raw):
    """As 9 colunas tipadas + faixa_hora, no grao de corrida (igual ao Lab 05)."""
    inicio = F.to_timestamp(F.col("data_corrida"))
    return raw.select(
        "corrida_id", "motorista_id", "passageiro_id", "bairro",
        inicio.alias("inicio"),
        F.to_timestamp(F.col("fim")).alias("fim"),
        "distancia_km", "duracao_min",
        F.regexp_replace(F.col("valor"), ",", ".").cast("double").alias("valor"),
        F.hour(inicio).alias("faixa_hora"),
        "dt",
    )


def gravar(df, destino, chaves, arquivos_por_pasta):
    """Grava em Parquet + Snappy, particionado por `chaves`.

    repartition(*chaves) junta cada pasta numa tarefa so: 1 arquivo por pasta.
    Com arquivos_por_pasta = k > 1, maxRecordsPerFile corta cada pasta em ~k arquivos.
    """
    df = df.repartition(*[F.col(c) for c in chaves])
    escrita = df.write.mode("overwrite").partitionBy(*chaves).option("compression", "snappy")
    if arquivos_por_pasta > 1:
        maior = df.groupBy(*chaves).count().agg(F.max("count")).first()[0]
        escrita = escrita.option("maxRecordsPerFile", -(-maior // arquivos_por_pasta))
    escrita.parquet(destino)


def main():
    import boto3
    from awsglue.context import GlueContext
    from awsglue.utils import getResolvedOptions
    from pyspark.context import SparkContext

    args = getResolvedOptions(sys.argv, ["BUCKET", "CHAVES", "ARQUIVOS_POR_PASTA"])
    bucket = args["BUCKET"]
    chaves = [c.strip() for c in args["CHAVES"].split(",") if c.strip()]
    arquivos = int(args["ARQUIVOS_POR_PASTA"])
    if chaves[0] != "dt":
        raise ValueError("a primeira chave de particao precisa ser dt (a pergunta filtra por data)")

    sc = SparkContext.getOrCreate()
    spark = GlueContext(sc).spark_session
    spark.conf.set("spark.sql.session.timeZone", "UTC")
    spark.conf.set("spark.sql.sources.partitionColumnTypeInference.enabled", "false")

    raw = spark.read.schema(SCHEMA_RAW).json(f"s3://{bucket}/raw/corridas/")
    trusted = transformar(raw).cache()
    gravar(trusted, f"s3://{bucket}/trusted/corridas/", chaves, arquivos)

    # Conferencia: rele a saida e mede no S3 quantos arquivos e bytes ela ocupa.
    s3 = boto3.client("s3")
    n_arq, n_bytes = 0, 0
    for pagina in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="trusted/corridas/"):
        for obj in pagina.get("Contents", []):
            if obj["Key"].endswith(".parquet"):
                n_arq += 1
                n_bytes += obj["Size"]
    saida = spark.read.parquet(f"s3://{bucket}/trusted/corridas/")
    relatorio = {
        "chaves": chaves,
        "arquivos_por_pasta": arquivos,
        "linhas_raw": raw.count(),
        "linhas_trusted": saida.count(),
        "dias": saida.select("dt").distinct().count(),
        "pastas": saida.select(*chaves).distinct().count(),
        "arquivos": n_arq,
        "bytes": n_bytes,
        "valor_nulo": saida.filter(F.col("valor").isNull()).count(),
    }
    relatorio["ok"] = (relatorio["linhas_trusted"] == relatorio["linhas_raw"]
                       and relatorio["valor_nulo"] == 0)
    texto = json.dumps(relatorio, indent=2)
    print(texto)
    s3.put_object(Bucket=bucket, Key="relatorios/trusted-parquet.json",
                  Body=texto.encode("utf-8"), ContentType="application/json")
    if not relatorio["ok"]:
        raise RuntimeError("conferencia falhou: " + texto)


if __name__ == "__main__":
    main()
