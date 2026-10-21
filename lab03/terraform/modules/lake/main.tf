# =============================================================================
# modulo lake: os seis recursos que antes viviam na raiz.
#
# Vieram da raiz SEM NENHUMA ALTERACAO: mesmos nomes de bloco, mesmas
# propriedades, mesmas expressoes. Refatorar e reorganizar, nao rebatizar:
# renomear qualquer um deles faria o Terraform tratar como recurso novo, e o
# plan deixaria de ser limpo.
#
# O que muda nao esta aqui: e o ENDERECO no estado, que ganha o prefixo
# `module.lake`. Quem conserta isso e o `terraform state mv`, nao o codigo.
# =============================================================================

resource "aws_s3_bucket" "lake" {
  bucket        = "eda-a12-${var.sufixo}-lake"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "results" {
  bucket        = "eda-a12-${var.sufixo}-results"
  force_destroy = true
}

resource "aws_glue_catalog_database" "db" {
  name = "eda_a12_${var.sufixo}"
}

resource "aws_glue_catalog_table" "corridas" {
  name          = "corridas"
  database_name = aws_glue_catalog_database.db.name
  table_type    = "EXTERNAL_TABLE"
  parameters    = { classification = "json" }

  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.lake.bucket}/raw/corridas/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info { serialization_library = "org.openx.data.jsonserde.JsonSerDe" }

    columns {
      name = "corrida_id"
      type = "string"
    }
    columns {
      name = "bairro"
      type = "string"
    }
    columns {
      name = "valor"
      type = "double"
    }
  }
}

resource "aws_athena_workgroup" "wg" {
  name          = "eda-a12-${var.sufixo}-wg"
  state         = "ENABLED"
  force_destroy = true
  configuration {
    enforce_workgroup_configuration = true
    bytes_scanned_cutoff_per_query  = var.teto_bytes
    result_configuration { output_location = "s3://${aws_s3_bucket.results.bucket}/athena-results/" }
  }
}
