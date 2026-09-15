# VEM PRONTO. Estado LOCAL de propósito: é o ponto de partida que você vai refatorar.
# Você ADICIONA o backend remoto durante o exercício (não está aqui ainda).
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
