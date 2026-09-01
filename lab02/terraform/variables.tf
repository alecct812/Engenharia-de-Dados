# =============================================================================
# PARCIAL — as variaveis estao declaradas; voce preenche os valores no arquivo
# terraform.tfvars (copie de terraform.tfvars.example) ou via -var.
# =============================================================================

variable "regiao" {
  type        = string
  default     = "us-east-1"
  description = "Regiao da AWS. Nao mude."
}

variable "turma" {
  type        = string
  default     = "2026-2"
  description = "Identificador da turma; entra nas tags."
}

variable "sufixo" {
  type        = string
  description = "Sufixo unico dos nomes (ex.: seu login). So minusculas, numeros e hifen."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.sufixo))
    error_message = "Use apenas letras minusculas, numeros e hifen."
  }
}

# DECISAO 05 — o teto de bytes por consulta (Athena).
# NAO copie um numero do lab. Meça: rode a consulta larga sem teto uma vez, veja
# o Data scanned, e escolha um teto que MATE a larga e DEIXE PASSAR a estreita.
# Justifique em DECISOES.md de que medicao ele saiu.
# O Athena recusa abaixo de 10485760 (10 MB); acima de 117455962 o freio nunca toca.
variable "teto_bytes" {
  type        = number
  description = "BytesScannedCutoffPerQuery do workgroup. Voce decide o valor (DECISAO 05)."

  validation {
    condition     = var.teto_bytes >= 10485760 && var.teto_bytes <= 117455962
    error_message = "O teto deve ficar entre 10485760 (10 MB) e 117455962."
  }
}

# DECISAO 04 — quantos dias de particao registrar.
# O lab registrou 1 particao. Aqui o criterio exige no minimo 3, e uma delas
# precisa ser a de hoje. Escolha quantos dias e justifique o que acontece com os
# dias que voce NAO registrou (e o que acontece amanha).
variable "dias_particao" {
  type        = list(string)
  description = "Lista de dias (AAAA-MM-DD) a registrar como particao. Minimo 3, incluindo hoje."

  validation {
    condition     = length(var.dias_particao) >= 3
    error_message = "Registre no minimo 3 particoes (criterio 3)."
  }
}
