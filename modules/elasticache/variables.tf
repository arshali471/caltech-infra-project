###############################################################################
# modules/elasticache/variables.tf
# ElastiCache Serverless — fully managed Redis scaling with no node type,
# cluster count, or parameter groups. Capacity is defined in GB and ECPU/s.
###############################################################################

variable "cluster_id" {
  description = "Name for the ElastiCache Serverless cache (unique, lowercase, hyphen-separated)"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "major_engine_version" {
  description = "Redis major engine version (e.g. '7')"
  type        = string
  default     = "7"
}

variable "port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the serverless cache ENIs"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of VPC security group IDs"
  type        = list(string)
}

# ---- Serverless Capacity Limits --------------------------------------------

variable "max_data_storage_gb" {
  description = "Maximum data storage in GB for the serverless cache"
  type        = number
  default     = 10
}

variable "min_data_storage_gb" {
  description = "Minimum data storage in GB for the serverless cache"
  type        = number
  default     = 1
}

variable "max_ecpu_per_second" {
  description = "Maximum ECPU (ElastiCache Processing Units) per second"
  type        = number
  default     = 5000
}

variable "min_ecpu_per_second" {
  description = "Minimum ECPU per second"
  type        = number
  default     = 1000
}

# ---- Snapshots & Maintenance -----------------------------------------------

variable "snapshot_retention_limit" {
  description = "Days to retain automated snapshots (0 = disabled)"
  type        = number
  default     = 5
}

variable "daily_snapshot_time" {
  description = "Daily time (UTC HH:MM) to take snapshots"
  type        = string
  default     = "05:00"
}

# ---- KMS -------------------------------------------------------------------

variable "kms_deletion_window_in_days" {
  description = "Waiting period (days) before KMS key is deleted after destroy"
  type        = number
  default     = 7
}

# ---- CloudWatch Alarms -----------------------------------------------------

variable "alarm_evaluation_periods" {
  description = "Number of consecutive periods that must breach threshold to trigger alarm"
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Evaluation period length in seconds for CloudWatch alarms"
  type        = number
  default     = 120
}

variable "alarm_ecpu_threshold" {
  description = "ElastiCacheProcessingUnits threshold to trigger alarm"
  type        = number
  default     = 4000
}

variable "alarm_memory_threshold_gb" {
  description = "BytesUsedForCache threshold in GB to trigger alarm"
  type        = number
  default     = 8
}

# ---- Tags ------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

