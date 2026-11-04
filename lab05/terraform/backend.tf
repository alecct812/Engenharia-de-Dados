# Estado no backend remoto da disciplina (o mesmo do Exercício 04).
# Os valores ficam em backend.hcl, que NÃO vai para o repositório:
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
