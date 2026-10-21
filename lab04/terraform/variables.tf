variable "regiao" {
  type    = string
  default = "us-east-1"
}

variable "turma" {
  type        = string
  description = "Identificador da turma (vai na tag Turma)."
}

variable "owner" {
  type        = string
  description = "E-mail de quem responde pela stack (vai na tag Owner)."
}

variable "sufixo" {
  type        = string
  description = "Sufixo unico do grupo: so minusculas e numeros (o Glue nao aceita hifen)."
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.sufixo))
    error_message = "Use apenas letras minusculas e numeros."
  }
}

# DECISÃO 01 — a chave de partição da trusted. A primeira chave é sempre dt.
# Opções que a Aula 19 discutiu: ["dt"] ou ["dt", "bairro"]. Justifique em
# DECISOES.md com o número de arquivos que a pergunta da madrugada abre.
variable "chaves_particao" {
  type = list(string)
  validation {
    condition     = try(var.chaves_particao[0], "") == "dt"
    error_message = "A primeira chave precisa ser dt: a pergunta filtra por data."
  }
}

# DECISÃO 02 — quantos arquivos por pasta de partição (1 a 4).
# O job lê este número: veja gravar() em scripts/trusted-parquet.py.
variable "arquivos_por_pasta" {
  type = number
  validation {
    condition     = var.arquivos_por_pasta >= 1 && var.arquivos_por_pasta <= 4
    error_message = "Entre 1 e 4 arquivos por pasta (critério 3 da rubrica)."
  }
}

# DECISÃO 03 — a META de custo da pergunta da madrugada (7 dias), em bytes.
# Requisito: cabe em 1 MiB. Diga em DECISOES.md de que medição ela saiu.
variable "meta_bytes_madrugada" {
  type = number
  validation {
    condition     = var.meta_bytes_madrugada > 0 && var.meta_bytes_madrugada <= 1048576
    error_message = "A meta tem de caber em 1 MiB (1.048.576 bytes): é o requisito do exercício."
  }
}

# DECISÃO 04 — o TETO do workgroup (o freio), em bytes.
# Mínimo do Athena: 10 MiB. Ele precisa deixar a pergunta passar e barrar a
# consulta que lê todas as colunas (critério 5).
variable "teto_bytes" {
  type = number
  validation {
    condition     = var.teto_bytes >= 10485760
    error_message = "O Athena recusa teto abaixo de 10 MiB (10.485.760 bytes)."
  }
}
