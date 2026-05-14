variable "name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "master_username" {
  type      = string
  sensitive = true
}

variable "master_password" {
  type      = string
  sensitive = true
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

variable "min_acu" {
  type    = number
  default = 0.5
}

variable "max_acu" {
  type    = number
  default = 16
}

variable "engine" {
  type    = string
  default = "aurora-postgresql"
}

variable "engine_version" {
  type    = string
  default = "16.3"
}

variable "backup_retention_period" {
  type    = number
  default = 7
}

variable "preferred_backup_window" {
  type    = string
  default = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  type    = string
  default = "sun:05:00-sun:06:00"
}

variable "skip_final_snapshot" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "cloudwatch_logs_exports" {
  type    = list(string)
  default = ["postgresql"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
