# CONTRATO — o verifica.sh le estes nomes. Nao mude os nomes.
output "bucket_name" {
  value = aws_s3_bucket.lake.bucket
}
output "database_name" {
  value = aws_glue_catalog_database.lake.name
}
output "trusted_table_name" {
  value = aws_glue_catalog_table.trusted.name
}
output "job_name" {
  value = aws_glue_job.trusted.name
}
output "workgroup_name" {
  value = aws_athena_workgroup.wg.name
}
output "chaves_particao" {
  value = join(",", var.chaves_particao)
}
output "meta_bytes_madrugada" {
  value = var.meta_bytes_madrugada
}
output "teto_bytes" {
  value = var.teto_bytes
}
