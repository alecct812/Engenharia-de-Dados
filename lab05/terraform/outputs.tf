# A interface é contrato: o rodar-job.sh e o verifica.sh leem estes nomes.
output "bucket" { value = aws_s3_bucket.lake.id }
output "database" { value = aws_glue_catalog_database.lake.name }
output "tabela" { value = aws_glue_catalog_table.corridas.name }
output "job" { value = aws_glue_job.pipeline.name }
output "workgroup" { value = aws_athena_workgroup.wg.name }
output "decisoes" {
  value = {
    modo_escrita       = var.modo_escrita
    chave_dedup        = var.chave_dedup
    janela_atraso_dias = var.janela_atraso_dias
  }
}
