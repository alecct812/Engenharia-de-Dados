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

# DECISÃO 01 — o alcance da permissão da Prefeitura na refined (Aula 27, permissão por camada).
# banco:  todas as tabelas do database refined, inclusive as que forem criadas depois.
# tabela: só a madrugada_bairro; tabela nova na refined fica invisível até alguém conceder.
variable "escopo_prefeitura" {
  type        = string
  description = "banco ou tabela."
  validation {
    condition     = contains(["banco", "tabela"], var.escopo_prefeitura)
    error_message = "DECISÃO 01: escolha banco ou tabela."
  }
}

# DECISÃO 02 — as colunas da trusted que a analista NÃO vê (Aula 27, permissão por coluna).
# Só colunas de identificação podem entrar na lista; as outras a analista precisa para trabalhar.
variable "colunas_ocultas_analista" {
  type        = list(string)
  description = "Subconjunto de corrida_id, motorista_id, passageiro_id."
  validation {
    condition = length(var.colunas_ocultas_analista) > 0 && alltrue([
      for c in var.colunas_ocultas_analista : contains(["corrida_id", "motorista_id", "passageiro_id"], c)
    ])
    error_message = "DECISÃO 02: liste ao menos uma coluna, só entre corrida_id, motorista_id e passageiro_id."
  }
}

# DECISÃO 03 — o contrato da refined no catálogo (Aula 27, o catálogo como contrato).
# É o que um consumidor lê antes de escrever o SQL: o que a tabela responde, de quem é, quando muda.
variable "contrato_refined" {
  type = object({
    descricao   = string
    dono        = string
    atualizacao = string
    comentarios = object({ bairro = string, corridas = string, receita = string })
  })
  description = "Descrição (ao menos 40 caracteres), dono, atualização e o comentário de cada coluna da madrugada_bairro."
  validation {
    condition = (length(trimspace(var.contrato_refined.descricao)) >= 40
      && trimspace(var.contrato_refined.dono) != ""
      && trimspace(var.contrato_refined.atualizacao) != ""
    && alltrue([for c in values(var.contrato_refined.comentarios) : trimspace(c) != ""]))
    error_message = "DECISÃO 03: descrição com ao menos 40 caracteres; dono, atualização e os três comentários preenchidos."
  }
}
