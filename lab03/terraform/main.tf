# =============================================================================
# A RAIZ, depois da refatoracao. Os seis resource sairam daqui para
# modules/lake/ e no lugar deles ficou uma unica chamada de modulo.
#
# A fronteira (DECISAO 01): ficam na raiz o provider e suas default_tags, as
# variaveis que o usuario preenche, o backend e o contrato de outputs. Vao para
# o modulo os recursos, e so eles.
#
# ATENCAO A ORDEM: este arquivo sozinho NAO basta. Trocar o codigo muda o
# endereco de cada recurso, de aws_s3_bucket.lake para
# module.lake.aws_s3_bucket.lake, e o estado ainda guarda o endereco antigo.
# Um `apply` agora destruiria e recriaria os seis. Quem concilia isso e o
# `terraform state mv`, ANTES de qualquer apply.
# =============================================================================

module "lake" {
  source = "./modules/lake"

  sufixo     = var.sufixo
  teto_bytes = var.teto_bytes
}
