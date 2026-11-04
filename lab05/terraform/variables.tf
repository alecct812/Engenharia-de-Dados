variable "regiao" {
  type    = string
  default = "us-east-1"
}

variable "turma" {
  type        = string
  description = "Turma, na tag Turma."
}

variable "sufixo" {
  type        = string
  description = "Login do grupo: só minúsculas e números (o Glue recusa hífen no database)."
  validation {
    condition     = can(regex("^[a-z0-9]{3,20}$", var.sufixo))
    error_message = "O sufixo tem de ter de 3 a 20 letras minúsculas ou números, sem hífen."
  }
}

# DECISÃO 01 — modo de escrita (Aula 22, idempotência).
# append acrescenta arquivos; sobrescrever troca só as partições que o job escreve.
variable "modo_escrita" {
  type        = string
  description = "append ou sobrescrever."
  validation {
    condition     = contains(["append", "sobrescrever"], var.modo_escrita)
    error_message = "DECISÃO 01: escolha append ou sobrescrever."
  }
}

# DECISÃO 02 — a chave da linha (Aula 22, chaves).
# corrida_id: uma linha por corrida, mesmo que ela chegue duas vezes. nenhuma: grava o que vier.
variable "chave_dedup" {
  type        = string
  description = "corrida_id ou nenhuma."
  validation {
    condition     = contains(["corrida_id", "nenhuma"], var.chave_dedup)
    error_message = "DECISÃO 02: escolha corrida_id ou nenhuma."
  }
}

# DECISÃO 03 — janela de atraso, em dias (Aula 23, dado atrasado).
# Quantos dias depois do evento uma corrida ainda entra no processamento.
variable "janela_atraso_dias" {
  type        = number
  description = "De 0 a 7 dias."
  validation {
    condition     = var.janela_atraso_dias >= 0 && var.janela_atraso_dias <= 7
    error_message = "DECISÃO 03: a janela vai de 0 a 7 dias."
  }
}
