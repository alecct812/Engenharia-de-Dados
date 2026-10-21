# =============================================================================
# BACKEND REMOTO: a cura que o Exercicio 02 prometeu.
#
# O bloco fica VAZIO de proposito, com uma excecao: os valores concretos
# (bucket, key, region, tabela de trava) vivem em backend.hcl, que NAO e
# versionado, porque nomeia a conta. O init recebe o arquivo com
# -backend-config=backend.hcl.
#
# workspace_key_prefix so vale para workspaces NAO-default:
#   default  -> <key>
#   dev      -> eda-a12/dev/<key>
# O prefixo marca de quem sao os estados de workspace dentro de um bucket que
# atravessa varios exercicios do semestre.
# =============================================================================

terraform {
  backend "s3" {
    workspace_key_prefix = "eda-a12"
  }
}
