provider "aws" {
  region = var.regiao
  default_tags {
    tags = {
      Disciplina = "EDA"
      Aula       = "25"
      Turma      = var.turma
      Owner      = var.sufixo
    }
  }
}
