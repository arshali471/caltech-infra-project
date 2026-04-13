###############################################################################
# modules/aurora/variables.tf
###############################################################################

variable "cluster_identifier" {
  description = "Unique identifier for the Aurora cluster"
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

variable "engine" {
  description = "Aurora engine type"
  type        = string
  default     = "aurora-postgresql"
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "Aurora instance class. Set to 'db.serverless' for Aurora Serverless v2 (recommended). Ignored when min/max ACUs are set."
  type        = string
  default     = "db.serverless"
}

variable "instance_count" {
  description = "Number of Aurora instances (writer + readers). Minimum 1."
  type        = number
  default     = 2
}

# ---- Aurora Serverless v2 Capacity ------------------------------------------

variable "min_capacity_units" {
  description = "Minimum Aurora Capacity Units (ACUs) for Serverless v2 scaling. Minimum is 0.5 ACU."
  type        = number
  default     = 0.5
}

variable "max_capacity_units" {
  description = "Maximum Aurora Capacity Units (ACUs) for Serverless v2 scaling. Maximum is 128 ACUs."
  type        = number
  default     = 128
}

variable "subnet_group_name" {
  description = "DB subnet group name"
  type        = string
}

variable "security_group_ids" {
  description = "List of VPC security group IDs"
  type        = list(string)
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (1-35). 30+ recommended for production."
  type        = number
  default     = 30
}

variable "preferred_backup_window" {
  description = "Daily time range for automated backups (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly time range for maintenance (UTC)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting the cluster"
  type        = bool
  default     = false
}

# ---- KMS / Secrets Manager ---------------------------------------------------

variable "kms_deletion_window_in_days" {
  description = "Waiting period (days) before KMS key is deleted after destroy (7-30)"
  type        = number
  default     = 30
}

variable "secret_recovery_window_in_days" {
  description = "Recovery window (days) before Secrets Manager secret is permanently deleted (7-30)"
  type        = number
  default     = 30
}

# ---- Parameter Groups -------------------------------------------------------

variable "cluster_parameter_group_family" {
  description = "Aurora DB cluster parameter group family (e.g. aurora-postgresql15). Derived from engine_version when left empty."
  type        = string
  default     = ""
}

variable "instance_parameter_group_family" {
  description = "Aurora DB instance parameter group family (e.g. aurora-postgresql15). Derived from engine_version when left empty."
  type        = string
  default     = ""
}

variable "shared_preload_libraries" {
  description = "Comma-separated PostgreSQL shared preload libraries"
  type        = string
  default     = "pg_stat_statements,pgaudit"
}

variable "log_statement" {
  description = "PostgreSQL log_statement level (none, ddl, mod, all)"
  type        = string
  default     = "ddl"
}

variable "log_min_duration_statement" {
  description = "Log queries that take longer than this many milliseconds (-1 disables)"
  type        = number
  default     = 1000
}

# ---- Monitoring & Insights --------------------------------------------------

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 disables, valid: 0,1,5,10,15,30,60). 1 = max granularity."
  type        = number
  default     = 1
}

variable "performance_insights_retention" {
  description = "Performance Insights retention period in days (7 free, 731 = 2 years)"
  type        = number
  default     = 731
}

variable "cloudwatch_log_exports" {
  description = "List of Aurora log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql"]
}

# ---- Auto-Scaling -----------------------------------------------------------

variable "autoscaling_min_replicas" {
  description = "Minimum number of Aurora read replicas for auto-scaling"
  type        = number
  default     = 1
}

variable "autoscaling_max_replicas" {
  description = "Maximum number of Aurora read replicas for auto-scaling (10+ for 1M RPS)"
  type        = number
  default     = 10
}

variable "autoscaling_cpu_target" {
  description = "Target CPU utilisation (%) to trigger Aurora replica auto-scaling"
  type        = number
  default     = 70
}

variable "autoscaling_scale_in_cooldown" {
  description = "Cooldown period (seconds) before scaling in Aurora replicas"
  type        = number
  default     = 300
}

variable "autoscaling_scale_out_cooldown" {
  description = "Cooldown period (seconds) before scaling out Aurora replicas"
  type        = number
  default     = 300
}

# ---- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
