###############################################################################
# modules/rds/variables.tf
# Aurora PostgreSQL Serverless v2 (Debezium CDC source)
###############################################################################

variable "identifier" {
  description = "Unique identifier for the Aurora Serverless v2 CDC source cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "database_name" {
  description = "Name of the initial database"
  type        = string
}

variable "master_username" {
  description = "Master DB username"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (e.g. 15.4)"
  type        = string
  default     = "15.4"
}

variable "instance_count" {
  description = "Number of Aurora instances (writer + optional readers)"
  type        = number
  default     = 2
}

# ---- Serverless v2 Capacity -------------------------------------------------

variable "min_capacity_units" {
  description = "Minimum Aurora Capacity Units (ACUs) for Serverless v2 (minimum 0.5)"
  type        = number
  default     = 0.5
}

variable "max_capacity_units" {
  description = "Maximum Aurora Capacity Units (ACUs) for Serverless v2 (maximum 128)"
  type        = number
  default     = 64
}

# ---- Network ----------------------------------------------------------------

variable "subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "security_group_ids" {
  description = "VPC security group IDs"
  type        = list(string)
}

# ---- Parameter Groups -------------------------------------------------------

variable "parameter_group_family" {
  description = "Aurora cluster/instance parameter group family. Derived from engine_version when empty."
  type        = string
  default     = ""
}

variable "instance_parameter_group_family" {
  description = "Aurora instance parameter group family. Derived from engine_version when empty."
  type        = string
  default     = ""
}

# ---- CDC Configuration (Debezium) -------------------------------------------

variable "max_wal_senders" {
  description = "Maximum number of WAL sender processes (Debezium replication connections)"
  type        = number
  default     = 10
}

variable "max_replication_slots" {
  description = "Maximum number of logical replication slots (one per Debezium connector)"
  type        = number
  default     = 10
}

variable "log_statement" {
  description = "PostgreSQL log_statement level (none, ddl, mod, all)"
  type        = string
  default     = "ddl"
}

variable "log_min_duration_statement" {
  description = "Log queries longer than this many milliseconds (-1 disables)"
  type        = number
  default     = 1000
}

# ---- Backup & Maintenance ---------------------------------------------------

variable "backup_retention_period" {
  description = "Days to retain automated backups (1-35). 30+ recommended for production."
  type        = number
  default     = 30
}

variable "preferred_backup_window" {
  description = "Daily backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window (UTC)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

# ---- Protection & Snapshots -------------------------------------------------

variable "deletion_protection" {
  description = "Enable deletion protection on the cluster"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting"
  type        = bool
  default     = false
}

# ---- KMS / Secrets Manager --------------------------------------------------

variable "kms_deletion_window_in_days" {
  description = "Waiting period (days) before KMS key deletion (7-30)"
  type        = number
  default     = 30
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window (days) before Secrets Manager secret is permanently deleted (7-30)"
  type        = number
  default     = 30
}

# ---- Monitoring & Insights --------------------------------------------------

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0,1,5,10,15,30,60). 1 = max granularity."
  type        = number
  default     = 1
}

variable "performance_insights_retention" {
  description = "Performance Insights retention period in days (7 free, 731 = 2 years)"
  type        = number
  default     = 731
}

variable "cloudwatch_log_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql"]
}

# ---- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
