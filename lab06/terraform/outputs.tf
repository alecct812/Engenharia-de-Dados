# A interface é contrato: os scripts (carregar-raw, rodar-jobs, como, verifica) leem estes nomes.
output "bucket" { value = aws_s3_bucket.lake.id }
output "database_raw" { value = aws_glue_catalog_database.camada["raw"].name }
output "database_trusted" { value = aws_glue_catalog_database.camada["trusted"].name }
output "database_refined" { value = aws_glue_catalog_database.camada["refined"].name }
output "job_trusted" { value = aws_glue_job.trusted.name }
output "job_refined" { value = aws_glue_job.refined.name }
output "workgroup" { value = aws_athena_workgroup.wg.name }
output "papel_prefeitura" { value = aws_iam_role.perfil["prefeitura"].arn }
output "papel_analista" { value = aws_iam_role.perfil["analista"].arn }
output "decisoes" {
  value = {
    escopo_prefeitura        = var.escopo_prefeitura
    colunas_ocultas_analista = var.colunas_ocultas_analista
  }
}
