# =============================================================================
# CONTRATO — não mexa nos nomes. O verifica.sh lê exatamente estes cinco outputs.
# =============================================================================

output "bucket_name" {
  description = "Nome do bucket de dados do lake."
  value       = aws_s3_bucket.lake.bucket
}

output "database_name" {
  description = "Nome do database no Glue Data Catalog."
  value       = aws_glue_catalog_database.db.name
}

output "table_name" {
  description = "Nome da tabela de corridas."
  value       = aws_glue_catalog_table.corridas.name
}

output "workgroup_name" {
  description = "Nome do workgroup do Athena."
  value       = aws_athena_workgroup.wg.name
}

output "teto_bytes" {
  description = "Teto de bytes por consulta aplicado (DECISAO 05)."
  value       = var.teto_bytes
}

# Conveniencia (nao entra na nota): URL do editor do Athena.
output "console_url_athena" {
  description = "Abrir o editor do Athena no console."
  value       = "https://${var.regiao}.console.aws.amazon.com/athena/home?region=${var.regiao}#/query-editor"
}
