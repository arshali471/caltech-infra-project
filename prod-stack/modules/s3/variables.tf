variable "name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "data_lake_ia_transition_days" {
  type    = number
  default = 30
}

variable "data_lake_glacier_transition_days" {
  type    = number
  default = 90
}

variable "data_lake_noncurrent_expiry_days" {
  type    = number
  default = 90
}

variable "logs_expiry_days" {
  type    = number
  default = 90
}

variable "logs_noncurrent_expiry_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
