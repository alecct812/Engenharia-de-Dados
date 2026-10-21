# =============================================================================
# A fronteira de ENTRADA do modulo: o minimo que ele precisa receber para
# construir o lake. Tudo que nao esta aqui, o modulo nao ve, e essa e a
# vantagem de embrulhar: a raiz nao consegue vazar estado para dentro dele
# por acidente.
#
# Regiao e tags NAO entram: sao do provider, que fica na raiz. Um modulo que
# declara o proprio provider vira dificil de reusar e impossivel de instanciar
# duas vezes com contas diferentes.
# =============================================================================

variable "sufixo" {
  type        = string
  description = "Sufixo unico que nomeia os recursos (so minusculas e numeros; sem hifen, por causa do Glue)."
}

variable "teto_bytes" {
  type        = number
  description = "BytesScannedCutoffPerQuery do workgroup do Athena."
}
