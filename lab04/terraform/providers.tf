provider "aws" {
  region = var.regiao
  default_tags {
    tags = {
      Disciplina = "EDA"
      Aula       = "21"
      Turma      = var.turma
      Owner      = var.owner
    }
  }
}
