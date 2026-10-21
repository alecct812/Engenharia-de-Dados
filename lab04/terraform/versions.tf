terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Backend remoto da disciplina, configurado na hora do init:
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}
