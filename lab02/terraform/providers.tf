# =============================================================================
# VEM PRONTO — não precisa mexer.
# Regiao e tags obrigatorias da disciplina, aplicadas a todo recurso via
# default_tags (nao ponha tag recurso a recurso).
# =============================================================================

provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      Disciplina = "EDA"
      Aula       = "08"
      Turma      = var.turma
      Owner      = var.sufixo
    }
  }
}
