###############################################################################
# Root Variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment (poc | dev | uat | prod)"
  type        = string
  default     = "poc"

  validation {
    condition     = contains(["poc", "dev", "uat", "prod"], var.environment)
    error_message = "environment must be one of: poc, dev, uat, prod."
  }
}

variable "project" {
  description = "Project slug used in every resource name and tag (lowercase, no spaces)"
  type        = string
  default     = "cultech"
}

# ---- VPC -------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to deploy into"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ) — NAT GWs and Librechat EC2"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets — EC2 application workloads and MSK"
  type        = list(string)
  default     = ["10.0.16.0/20", "10.0.32.0/20"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private DB subnets — Aurora, RDS, ElastiCache"
  type        = list(string)
  default     = ["10.0.48.0/22", "10.0.52.0/22"]
}

variable "single_nat_gateway" {
  description = "Use one shared NAT Gateway (true = lower cost for POC/Dev; false = HA for UAT/Prod)"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateways for private subnet egress"
  type        = bool
  default     = true
}

variable "vpc_flow_log_retention_days" {
  description = "CloudWatch retention for VPC flow logs in days"
  type        = number
  default     = 7
}

# ---- EC2 Application Instances ---------------------------------------------

variable "ec2_instance_types" {
  description = "Instance type per application role"
  type        = map(string)
  default = {
    transaction_sim = "t3.small"
    debezium        = "t3.medium"
    redis_sink      = "t3.small"
    postgres_sink   = "t3.small"
    librechat       = "t3.small"
  }
}

# ---- Aurora PostgreSQL (Source / Primary DB) -------------------------------

variable "aurora_db_name" {
  description = "Initial database name for Aurora cluster"
  type        = string
  default     = "appdb"
}

variable "aurora_master_username" {
  description = "Master username for Aurora cluster"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "aurora_instance_count" {
  description = "Number of Aurora Serverless v2 instances (1 for POC, 3 for Prod)"
  type        = number
  default     = 1
}

variable "aurora_min_capacity_units" {
  description = "Minimum Aurora Capacity Units (ACUs)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity_units" {
  description = "Maximum Aurora Capacity Units (ACUs)"
  type        = number
  default     = 4
}

variable "aurora_autoscaling_max_replicas" {
  description = "Maximum Aurora read replicas for auto-scaling"
  type        = number
  default     = 1
}

# ---- RDS PostgreSQL (CDC Source + Sink DB) ---------------------------------

variable "rds_db_name" {
  description = "Initial database name for RDS PostgreSQL"
  type        = string
  default     = "sourcedb"
}

variable "rds_master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "rds_instance_count" {
  description = "Number of RDS CDC cluster instances"
  type        = number
  default     = 1
}

variable "rds_min_capacity_units" {
  description = "Minimum ACUs for RDS CDC Aurora Serverless v2"
  type        = number
  default     = 0.5
}

variable "rds_max_capacity_units" {
  description = "Maximum ACUs for RDS CDC Aurora Serverless v2"
  type        = number
  default     = 2
}

# ---- ElastiCache Redis -----------------------------------------------------

variable "redis_major_engine_version" {
  description = "Redis major engine version for ElastiCache Serverless"
  type        = string
  default     = "7"
}

variable "redis_max_data_storage_gb" {
  description = "Maximum data storage GB for ElastiCache Serverless Redis"
  type        = number
  default     = 10
}

variable "redis_min_data_storage_gb" {
  description = "Minimum data storage GB for ElastiCache Serverless Redis"
  type        = number
  default     = 1
}

variable "redis_max_ecpu_per_second" {
  description = "Maximum ECPU/s for ElastiCache Serverless Redis"
  type        = number
  default     = 10000
}

variable "redis_min_ecpu_per_second" {
  description = "Minimum ECPU/s for ElastiCache Serverless Redis"
  type        = number
  default     = 1000
}

# ---- Database Operational Parameters ---------------------------------------

variable "db_backup_retention_days" {
  description = "Automated backup retention in days for Aurora and RDS clusters"
  type        = number
  default     = 1
}

variable "db_performance_insights_retention" {
  description = "Performance Insights data retention in days (7 = free tier)"
  type        = number
  default     = 7
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0,1,5,10,15,30,60)"
  type        = number
  default     = 60
}

variable "kms_deletion_window" {
  description = "Waiting period (days) before a KMS CMK is deleted after terraform destroy (7-30)"
  type        = number
  default     = 7
}

variable "secret_recovery_window" {
  description = "Recovery window (days) before a Secrets Manager secret is permanently deleted (7-30)"
  type        = number
  default     = 7
}

# ---- Common Tags -----------------------------------------------------------

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Owner      = "platform-team"
    CostCenter = "engineering"
    Terraform  = "true"
    Project    = "cultech"
  }
}
