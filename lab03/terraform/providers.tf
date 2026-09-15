provider "aws" {
  region = var.regiao
  default_tags {
    tags = { Disciplina = "EDA", Aula = "12", Owner = var.sufixo }
  }
}
