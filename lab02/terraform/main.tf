# =============================================================================
# ESQUELETO — os blocos estao declarados; os campos que exigem DECISAO estao
# marcados com "# DECISAO NN". Complete-os e justifique cada um em DECISOES.md.
#
# Este arquivo NAO sobe como esta: as variaveis teto_bytes e dias_particao nao
# tem default (variables.tf). Voce precisa preenche-las em terraform.tfvars
# antes do primeiro apply. Isso e de proposito: sao as duas decisoes que o lab
# entregou prontas e que aqui sao suas.
#
# A interface (outputs.tf) e CONTRATO: o verifica.sh le aqueles nomes. Nao mexa.
# =============================================================================

# ---- Bucket de dados do lake --------------------------------------------------
resource "aws_s3_bucket" "lake" {
  bucket        = "eda-a08-lake-${var.sufixo}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- Bucket de resultados do Athena ------------------------------------------
resource "aws_s3_bucket" "results" {
  bucket        = "eda-a08-results-${var.sufixo}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---- Catalogo: database ------------------------------------------------------
resource "aws_glue_catalog_database" "db" {
  name = "eda_a08_lake_${var.sufixo}"
}

# ---- Catalogo: tabela com SCHEMA DECLARADO -----------------------------------
# Sem Crawler: as colunas sao escritas a mao. Tres campos exigem decisao.
resource "aws_glue_catalog_table" "corridas" {
  name          = "corridas"
  database_name = aws_glue_catalog_database.db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification = "json"
    # DECISAO 03 — barulho, nao silencio. Justificativa em DECISOES.md.
    # Sao DOIS defeitos diferentes, e cada um tem a sua chave:
    #   ignore.malformed.json     -> a LINHA nao e JSON valido
    #   use.null.for.invalid.data -> a linha e JSON valido, o VALOR nao cabe no tipo
    # O "17,82" que o enunciado cita e o segundo caso: so a primeira chave nao o cobre.
    "ignore.malformed.json"     = "false" # DECISAO 03
    "use.null.for.invalid.data" = "false" # DECISAO 03
  }

  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake.bucket}/raw/corridas/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      # As mesmas duas chaves aqui: o SerDe le as opcoes dele de ser_de_info,
      # e a leitura de uma tabela particionada usa o SerDe da PARTICAO.
      parameters = {
        "ignore.malformed.json"     = "false"
        "use.null.for.invalid.data" = "false"
      }
    }

    columns {
      name = "corrida_id"
      type = "string"
    }
    columns {
      name = "motorista_id"
      type = "string"
    }
    columns {
      name = "passageiro_id"
      type = "string"
    }
    columns {
      name = "bairro"
      type = "string"
    }

    # DECISAO 02 — colunas de tempo: string.
    # Medido nas 128.000 linhas: 100% chegam como "HH:MM:SS", hora do dia SEM data.
    # timestamp no Athena espera "AAAA-MM-DD HH:MM:SS" e devolveria null em toda
    # linha — falha silenciosa, exatamente o que esta entrega recusa.
    columns { # DECISAO 02
      name = "data_corrida"
      type = "string"
    }
    columns { # DECISAO 02
      name = "fim"
      type = "string"
    }

    columns {
      name = "distancia_km"
      type = "double"
    }
    columns {
      name = "duracao_min"
      type = "int"
    }

    # DECISAO 01 — o tipo de "valor".
    # double converte sozinho, mas os 1,5% de eventos com "17,82" (virgula) viram null.
    # string nao perde nada e cobra um cast de toda consulta futura.
    # decimal(10,2) e o tipo do dinheiro. Diga o que voce ACEITA PERDER. (default: double)
    columns { # DECISAO 01
      name = "valor"
      type = "decimal(10,2)"
    }
  }
}

# ---- Catalogo: particoes (>= 3, uma delas a de hoje) -------------------------
# DECISAO 04 — quantos dias registrar (via var.dias_particao, no tfvars).
# ARMADILHA: o "location" de cada particao PRECISA bater com a chave real do
# objeto no S3 (raw/corridas/dt=DIA/...). Se nao bater, o Athena devolve ZERO
# linhas SEM ERRO NENHUM, e os criterios 3 e 4 caem juntos.
resource "aws_glue_partition" "p" {
  for_each = toset(var.dias_particao)

  database_name    = aws_glue_catalog_database.db.name
  table_name       = aws_glue_catalog_table.corridas.name
  partition_values = [each.value]

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake.bucket}/raw/corridas/dt=${each.value}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      # As mesmas duas chaves aqui: o SerDe le as opcoes dele de ser_de_info,
      # e a leitura de uma tabela particionada usa o SerDe da PARTICAO.
      parameters = {
        "ignore.malformed.json"     = "false"
        "use.null.for.invalid.data" = "false"
      }
    }

    columns {
      name = "corrida_id"
      type = "string"
    }
    columns {
      name = "motorista_id"
      type = "string"
    }
    columns {
      name = "passageiro_id"
      type = "string"
    }
    columns {
      name = "bairro"
      type = "string"
    }
    columns {
      name = "data_corrida"
      type = "string"
    }
    columns {
      name = "fim"
      type = "string"
    }
    columns {
      name = "distancia_km"
      type = "double"
    }
    columns {
      name = "duracao_min"
      type = "int"
    }
    columns {
      name = "valor"
      type = "decimal(10,2)"
    }
  }
}

# ---- Consulta: workgroup do Athena com o teto de bytes -----------------------
# DECISAO 05 — o teto (var.teto_bytes, no tfvars), que voce MEDIU.
resource "aws_athena_workgroup" "wg" {
  name          = "eda-a08-wg-${var.sufixo}"
  state         = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false
    bytes_scanned_cutoff_per_query     = var.teto_bytes

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.bucket}/athena-results/"
    }
  }
}
