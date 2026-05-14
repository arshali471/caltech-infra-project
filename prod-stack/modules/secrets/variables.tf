variable "name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "aurora_source_master_username" {
  type      = string
  sensitive = true
}

variable "aurora_sink_master_username" {
  type      = string
  sensitive = true
}

variable "secret_recovery_window_days" {
  type    = number
  default = 30
}

variable "password_length" {
  type    = number
  default = 32
}

variable "password_special_chars" {
  type    = string
  default = "!#$%&*()-_=+[]{}<>:?"
}

variable "tags" {
  type    = map(string)
  default = {}
}
