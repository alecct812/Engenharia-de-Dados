# =============================================================================
# VEM PRONTO — não precisa mexer.
# Versao minima do Terraform e do provider AWS (travada).
#
# NOTA SOBRE O ESTADO: este exercicio roda com STATE LOCAL, de proposito.
# Nao existe backend.tf. O terraform.tfstate vai nascer nesta pasta, no seu
# laptop — e voce vai sentir a dor disso. A cura (estado remoto, com trava) e
# o Ciclo 3. Nao adicione backend aqui.
# =============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
