# =============================================================================
# Exercício 04 (Aula 21) — PONTO DE PARTIDA. O que vem pronto e o que é seu.
#
# Vem pronto: bucket, raw declarada, papel, job e workgroup. É seu: as cinco
# DECISÕES (variables.tf e os dois pontos marcados abaixo) e o DECISOES.md.
# Mesma ideia do Lab 05, com três diferenças:
#   1. Terraform, na conta do grupo, com backend remoto;
#   2. uma trusted só, com o layout que o grupo decidiu (DECISÕES 01 e 02);
#   3. uma META de bytes para a pergunta da madrugada, provada no verifica.sh.
# =============================================================================

locals {
  nome = "eda-a21"

  # As 10 colunas da trusted (as mesmas do Lab 05). A coluna que vira chave de
  # partição sai daqui: ela passa a morar no caminho, não dentro do arquivo.
  colunas = [
    { nome = "corrida_id", tipo = "string" },
    { nome = "motorista_id", tipo = "string" },
    { nome = "passageiro_id", tipo = "string" },
    { nome = "bairro", tipo = "string" },
    { nome = "inicio", tipo = "timestamp" },
    { nome = "fim", tipo = "timestamp" },
    { nome = "distancia_km", tipo = "double" },
    { nome = "duracao_min", tipo = "double" },
    { nome = "valor", tipo = "double" },
    { nome = "faixa_hora", tipo = "int" },
  ]
  colunas_dados = [for c in local.colunas : c if !contains(var.chaves_particao, c.nome)]

  bairros = [
    "Aflitos", "Boa Viagem", "Boa Vista", "Bongi", "Casa Forte", "Caxangá",
    "Cordeiro", "Derby", "Encruzilhada", "Espinheiro", "Graças", "Ilha do Leite",
    "Imbiribeira", "Jaqueira", "Madalena", "Pina", "Recife Antigo", "Santo Amaro",
    "Setúbal", "Tamarineira", "Torre", "Várzea",
  ]

  # DECISÃO 05 — como o Athena descobre as partições. Duas saídas defensáveis:
  #   (a) deixar este mapa vazio e o rodar-job.sh roda MSCK REPAIR TABLE depois
  #       de cada execução do job (o catálogo guarda cada pasta);
  #   (b) partition projection: o Athena calcula as pastas por uma regra, sem
  #       registrar nada. Parâmetros: projection.enabled, projection.dt.type
  #       (date), projection.dt.format, projection.dt.range, projection.dt.interval,
  #       projection.dt.interval.unit e storage.location.template — este último
  #       pronto em local.template_caminho. Com bairro na chave, projection.bairro
  #       do tipo enum, com local.bairros.
  # Documentação: Amazon Athena User Guide, "Partition projection".
  local_trusted = "s3://${aws_s3_bucket.lake.bucket}/trusted/corridas"
  template_caminho = join("/", concat(
    [local.local_trusted],
    [for k in var.chaves_particao : "${k}=$${${k}}"],
  ))
  # DECISÃO 05: partition projection. O Athena calcula as pastas por esta regra,
  # sem nada registrado no catálogo, e o dia que chega amanhã aparece sozinho.
  # O início é fixo e anterior a qualquer dado do gerador: uma janela móvel
  # ("os últimos 30 dias") esconderia o dia mais antigo a cada amanhecer, sem erro.
  # A chave bairro só entra na regra se estiver em chaves_particao.
  projecao = merge(
    {
      "projection.enabled"          = "true"
      "projection.dt.type"          = "date"
      "projection.dt.format"        = "yyyy-MM-dd"
      "projection.dt.range"         = "2026-01-01,NOW"
      "projection.dt.interval"      = "1"
      "projection.dt.interval.unit" = "DAYS"
      "storage.location.template"   = local.template_caminho
    },
    contains(var.chaves_particao, "bairro") ? {
      "projection.bairro.type"   = "enum"
      "projection.bairro.values" = join(",", local.bairros)
    } : {}
  )

}

# ---------------------------------------------------------------- armazenamento

# O bucket do lake: raw/, trusted/, scripts/, relatorios/ e resultados do Athena.
resource "aws_s3_bucket" "lake" {
  bucket        = "${local.nome}-lake-${var.sufixo}"
  force_destroy = true # destroy limpo é critério de aceite
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# O script do job vai para o S3 no próprio apply; o etag faz o apply perceber
# quando o script muda.
resource "aws_s3_object" "script" {
  bucket = aws_s3_bucket.lake.id
  key    = "scripts/trusted-parquet.py"
  source = "${path.module}/scripts/trusted-parquet.py"
  etag   = filemd5("${path.module}/scripts/trusted-parquet.py")
}

# ---------------------------------------------------------------- catálogo

resource "aws_glue_catalog_database" "lake" {
  name = "eda_a21_${var.sufixo}"
}

# O CRU, igual ao dos Labs 04 e 05: JSON, 9 colunas, valor como string, partição dt.
resource "aws_glue_catalog_table" "raw" {
  name          = "raw_corridas"
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    classification = "json"
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
      type = "double"
    }
    columns {
      name = "valor"
      type = "string"
    }
  }
}

# A TRUSTED em Parquet. Formato (3 linhas), partição (DECISÃO 01) e o registro
# das partições (DECISÃO 05) estão aqui; as colunas vêm de local.colunas_dados.
resource "aws_glue_catalog_table" "trusted" {
  name          = "trusted_corridas"
  database_name = aws_glue_catalog_database.lake.name
  table_type    = "EXTERNAL_TABLE"
  parameters = merge(
    {
      classification        = "parquet"
      "parquet.compression" = "SNAPPY"
    },
    local.projecao
  )

  dynamic "partition_keys" {
    for_each = var.chaves_particao
    content {
      name = partition_keys.value
      type = "string"
    }
  }

  storage_descriptor {
    location = "${local.local_trusted}/"
    # As três linhas que fazem a tabela ser Parquet: as mesmas da corridas_parquet
    # do Lab 05 (infra/template.yaml, linhas 134, 135 e 137).
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    dynamic "columns" {
      for_each = local.colunas_dados
      content {
        name = columns.value.nome
        type = columns.value.tipo
      }
    }
  }
}

# ---------------------------------------------------------------- o job

resource "aws_iam_role" "glue" {
  name = "${local.nome}-glue-${var.sufixo}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# O job lê e escreve só neste bucket.
resource "aws_iam_role_policy" "glue_bucket" {
  name = "${local.nome}-bucket-rw"
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
    }]
  })
}

# 2 workers G.1X = 2 DPU. Timeout de 20 min: teto de custo se algo travar.
# O layout (DECISÕES 01 e 02) chega ao script como argumento: está declarado aqui.
resource "aws_glue_job" "trusted" {
  name              = "${local.nome}-trusted-${var.sufixo}"
  role_arn          = aws_iam_role.glue.arn
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 20
  max_retries       = 0

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${aws_s3_bucket.lake.bucket}/${aws_s3_object.script.key}"
  }

  default_arguments = {
    "--BUCKET"              = aws_s3_bucket.lake.bucket
    "--CHAVES"              = join(",", var.chaves_particao)
    "--ARQUIVOS_POR_PASTA"  = tostring(var.arquivos_por_pasta)
    "--job-language"        = "python"
    "--job-bookmark-option" = "job-bookmark-disable"
  }
}

# ---------------------------------------------------------------- a consulta

# O workgroup com o teto (DECISÃO 04). enforce = o teto vale para todo mundo que
# consulta por aqui, sem exceção de cliente.
resource "aws_athena_workgroup" "wg" {
  name          = "${local.nome}-wg-${var.sufixo}"
  state         = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false
    bytes_scanned_cutoff_per_query     = var.teto_bytes

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"
    }
  }
}
