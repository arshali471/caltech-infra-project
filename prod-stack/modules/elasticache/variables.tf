variable "name" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "engine" {
  type    = string
  default = "redis"
}

variable "min_data_storage_gb" {
  type    = number
  default = 1
}

variable "max_data_storage_gb" {
  type    = number
  default = 100
}

variable "min_ecpu_per_second" {
  type    = number
  default = 1000
}

variable "max_ecpu_per_second" {
  type    = number
  default = 500000
}

variable "tags" {
  type    = map(string)
  default = {}
}
