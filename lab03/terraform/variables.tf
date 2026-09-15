variable "regiao" {
  type    = string
  default = "us-east-1"
}
variable "sufixo" {
  type        = string
  description = "Sufixo unico (so minusculas e numeros; sem hifen, por causa do Glue)."
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.sufixo))
    error_message = "Use apenas letras minusculas e numeros (sem hifen)."
  }
}
variable "teto_bytes" {
  type    = number
  default = 20971520
}
