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

# Limitless capacity range (ACUs) — applied at the shard group level
variable "min_acu" {
  type    = number
  default = 24
}

variable "max_acu" {
  type    = number
  default = 384
}

variable "compute_redundancy" {
  description = "0 = single AZ, 1 = one standby, 2 = two standbys"
  type        = number
  default     = 0
}

variable "engine" {
  type    = string
  default = "aurora-postgresql"
}

# Aurora Limitless requires a -limitless engine version (e.g. 16.6-limitless)
variable "engine_version" {
  type    = string
  default = "16.13-limitless"
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

variable "max_replication_slots" {
  type    = number
  default = 10
}

variable "max_wal_senders" {
  type    = number
  default = 10
}

variable "wal_sender_timeout_ms" {
  type    = number
  default = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
