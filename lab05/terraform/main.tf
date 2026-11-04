locals {
  nome   = "eda-a25-${var.sufixo}"
  bucket = "eda-a25-lake-${var.sufixo}"
  banco  = "eda_a25_${var.sufixo}"
  # partition projection: o Athena calcula as pastas dt= por regra (DECISÃO 05 do Exercício 04)
  projecao = {
    "projection.enabled"          = "true"
    "projection.dt.type"          = "date"
    "projection.dt.format"        = "yyyy-MM-dd"
    "projection.dt.range"         = "NOW-60DAYS,NOW+1DAYS"
    "projection.dt.interval"      = "1"
    "projection.dt.interval.unit" = "DAYS"
  }
  colunas_trusted = [
    ["corrida_id", "string"], ["motorista_id", "string"], ["passageiro_id", "string"], ["bairro", "string"],
    ["inicio", "timestamp"], ["fim", "timestamp"], ["distancia_km", "double"], ["duracao_min", "double"],
    ["valor", "double"], ["faixa_hora", "int"], ["chegada", "string"],
  ]
  colunas_raw = [
    ["corrida_id", "string"], ["motorista_id", "string"], ["passageiro_id", "string"], ["bairro", "string"],
    ["data_corrida", "string"], ["fim", "string"], ["distancia_km", "double"], ["duracao_min", "double"],
    ["valor", "string"],
  ]
}

# 1. Bucket do lake: raw/, trusted/, scripts/, relatorios/, athena-results/.
resource "aws_s3_bucket" "lake" {
  bucket        = local.bucket
  force_destroy = true
}

resource "aws_glue_catalog_database" "lake" {
  name = local.banco
}

# 2. A raw: JSON, dt = dia de CHEGADA do arquivo.
resource "aws_glue_catalog_table" "raw" {
  name          = "raw_corridas"
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"
  parameters = merge(local.projecao, {
    "classification"            = "json"
    "storage.location.template" = "s3://${local.bucket}/raw/corridas/dt=$${dt}/"
  })
  partition_keys {
    name = "dt"
    type = "string"
  }
  storage_descriptor {
    location      = "s3://${local.bucket}/raw/corridas/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }
    dynamic "columns" {
      for_each = local.colunas_raw
      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }
}

# 3. A trusted: Parquet, dt = dia do EVENTO. É a tabela que o painel lê.
resource "aws_glue_catalog_table" "corridas" {
  name          = "corridas"
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"
  parameters = merge(local.projecao, {
    "classification"            = "parquet"
    "storage.location.template" = "s3://${local.bucket}/trusted/corridas/dt=$${dt}/"
  })
  partition_keys {
    name = "dt"
    type = "string"
  }
  storage_descriptor {
    location      = "s3://${local.bucket}/trusted/corridas/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }
    dynamic "columns" {
      for_each = local.colunas_trusted
      content {
        name = columns.value[0]
        type = columns.value[1]
      }
    }
  }
}

# 4. O papel do job: lê e escreve só neste bucket.
resource "aws_iam_role" "job" {
  name = "${local.nome}-glue"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue" {
  role       = aws_iam_role.job.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "bucket" {
  name = "bucket-rw"
  role = aws_iam_role.job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
    }]
  })
}

# 5. O script do job (o mesmo do Lab 06). etag: mudou o arquivo, o apply sobe de novo.
resource "aws_s3_object" "script" {
  bucket = aws_s3_bucket.lake.id
  key    = "scripts/pipeline-corridas.py"
  source = "${path.module}/scripts/pipeline-corridas.py"
  etag   = filemd5("${path.module}/scripts/pipeline-corridas.py")
}

# 6. O job. As três decisões chegam como argumento: o script não muda entre grupos.
resource "aws_glue_job" "pipeline" {
  name              = "${local.nome}-pipeline"
  role_arn          = aws_iam_role.job.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 15
  max_retries       = 0
  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.lake.id}/${aws_s3_object.script.key}"
  }
  default_arguments = {
    "--BUCKET" = aws_s3_bucket.lake.id
    "--TABELA" = "corridas"
    "--DIAS"   = "todos"
    # As três decisões do grupo (variables.tf). Ligue cada argumento à sua variável.
    # DECISÃO 01 — o modo de escrita decide o que acontece quando o job roda de novo.
    "--MODO" = var.modo_escrita
    # DECISÃO 02 — a chave decide o que acontece quando a mesma corrida chega duas vezes.
    "--CHAVE" = var.chave_dedup
    # DECISÃO 03 — a janela decide até quantos dias de atraso uma corrida ainda entra.
    "--JANELA"              = tostring(var.janela_atraso_dias)
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
  }
}

# 7. O workgroup: teto de 200 MiB e resultados no próprio bucket.
resource "aws_athena_workgroup" "wg" {
  name          = "${local.nome}-wg"
  force_destroy = true
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false
    bytes_scanned_cutoff_per_query     = 209715200
    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.id}/athena-results/"
    }
  }
}
