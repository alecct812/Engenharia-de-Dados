# =============================================================================
# A fronteira de SAIDA do modulo: o que ele expoe para cima. Sao exatamente os
# cinco nomes do contrato do exercicio, para que a raiz possa repassa-los sem
# precisar alcancar recurso nenhum la dentro.
#
# Quem quiser o nome do bucket pede module.lake.bucket_name. Ninguem de fora
# referencia module.lake.aws_s3_bucket.lake.bucket: isso seria furar a
# fronteira, e prenderia a raiz ao nome interno do recurso.
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
  description = "Teto de bytes por consulta efetivamente aplicado no workgroup."
  value       = aws_athena_workgroup.wg.configuration[0].bytes_scanned_cutoff_per_query
}

output "results_bucket_name" {
  description = "Bucket onde o Athena grava os resultados (nao faz parte do contrato)."
  value       = aws_s3_bucket.results.bucket
}
