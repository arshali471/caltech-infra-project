###############################################################################
# Root Variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-1"
}

variable "environment" {
  description = "Deployment environment. Drives naming, retention and capacity across all modules. Valid: poc | dev | uat | prod"
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

# ---- VPC ---------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to use (us-west-1 has only 2 AZs)"
  type        = list(string)
  default     = ["us-west-1a", "us-west-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ) — /24 sufficient for ALB ENIs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets — /20 gives 4091 IPs per AZ for EKS Fargate pods (one ENI per pod)"
  type        = list(string)
  default     = ["10.0.16.0/20", "10.0.32.0/20"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private DB subnets — /22 gives 1022 IPs per AZ for Aurora/Redis serverless ENIs"
  type        = list(string)
  default     = ["10.0.48.0/22", "10.0.52.0/22"]
}

variable "single_nat_gateway" {
  description = "Use one shared NAT Gateway instead of one per AZ. true = lower cost (POC/Dev); false = HA (UAT/Prod)"
  type        = bool
  default     = true
}

# ---- EKS ---------------------------------------------------------------

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster (1.32 is the latest stable as of April 2026)"
  type        = string
  default     = "1.32"
}

variable "eks_endpoint_public_access" {
  description = "Allow public access to the EKS API server endpoint"
  type        = bool
  default     = false
}

variable "eks_public_access_cidrs" {
  description = "CIDRs allowed to access the public EKS endpoint (if enabled)"
  type        = list(string)
  default     = []
}

variable "eks_fargate_profiles" {
  description = "EKS Fargate profile configurations. Each profile maps to one or more Kubernetes namespace selectors."
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
  }))
  default = {
    apps = {
      selectors = [
        { namespace = "default", labels = {} },
        { namespace = "production", labels = {} }
      ]
    }
    debezium = {
      selectors = [
        { namespace = "debezium", labels = {} }
      ]
    }
  }
}

# ---- MSK Serverless (Kafka) --------------------------------------------
# MSK Serverless manages all brokers, storage, and scaling automatically.
# No broker instance type, EBS volume, or node count is configurable.

# ---- Aurora PostgreSQL -------------------------------------------------

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
  description = "Number of Aurora Serverless v2 instances. POC: 1. Prod: 3 (writer + 2 readers)."
  type        = number
  default     = 1
}

variable "aurora_min_capacity_units" {
  description = "Minimum Aurora Capacity Units (ACUs) for Aurora Serverless v2 (minimum 0.5)"
  type        = number
  default     = 0.5
}

variable "aurora_max_capacity_units" {
  description = "Maximum Aurora Capacity Units (ACUs). POC: 4. Prod: 128 (maximum = 256 GiB RAM)."
  type        = number
  default     = 4
}

# ---- RDS PostgreSQL ----------------------------------------------------

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
  description = "Number of Aurora Serverless v2 CDC cluster instances. POC: 1. Prod: 2 (HA)."
  type        = number
  default     = 1
}

variable "rds_min_capacity_units" {
  description = "Minimum Aurora Capacity Units (ACUs) for CDC Aurora Serverless v2 (minimum 0.5)"
  type        = number
  default     = 0.5
}

variable "rds_max_capacity_units" {
  description = "Maximum Aurora Capacity Units (ACUs) for CDC Aurora Serverless v2. POC: 2. Prod: 64."
  type        = number
  default     = 2
}

# ---- ElastiCache Redis -------------------------------------------------

variable "redis_major_engine_version" {
  description = "Redis major engine version for ElastiCache Serverless (e.g. '7')"
  type        = string
  default     = "7"
}

variable "redis_max_data_storage_gb" {
  description = "Maximum data storage GB for ElastiCache Serverless Redis. POC: 10. Prod: 1000 (1 TB)."
  type        = number
  default     = 10
}

variable "redis_min_data_storage_gb" {
  description = "Minimum data storage in GB for ElastiCache Serverless Redis"
  type        = number
  default     = 1
}

variable "redis_max_ecpu_per_second" {
  description = "Maximum ECPU/s for ElastiCache Serverless Redis. POC: 10000. Prod: 5000000 (1M RPS × 5 ops). AWS max: 15M."
  type        = number
  default     = 10000
}

variable "redis_min_ecpu_per_second" {
  description = "Minimum ECPU per second for ElastiCache Serverless Redis"
  type        = number
  default     = 1000
}

# ---- ALB ---------------------------------------------------------------

variable "alb_deletion_protection" {
  description = "Enable ALB deletion protection. Disable in POC/Dev for easy teardown."
  type        = bool
  default     = false
}

variable "alb_ssl_certificate_arn" {
  description = "ARN of the ACM SSL certificate for HTTPS listener"
  type        = string
  default     = ""
}

# ---- Common Tags -------------------------------------------------------

variable "tags" {
  description = "Common tags applied to all resources (merged with module-level tags)"
  type        = map(string)
  default = {
    Owner      = "platform-team"
    CostCenter = "engineering"
    Terraform  = "true"
    Project    = "cultech"
  }
}

# ---- VPC advanced ------------------------------------------------------

variable "enable_nat_gateway" {
  description = "Create NAT Gateways so private subnets can reach the internet (ECR pulls, AWS APIs). Disable only for air-gapped deployments."
  type        = bool
  default     = true
}

variable "vpc_flow_log_retention_days" {
  description = "CloudWatch Logs retention in days for VPC flow logs. POC: 7 days. Prod: 90 days."
  type        = number
  default     = 7
}

# ---- EKS advanced ------------------------------------------------------

variable "eks_enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA). Required for pods to access AWS services without node-level credentials."
  type        = bool
  default     = true
}

variable "eks_endpoint_private_access" {
  description = "Enable private (VPC-internal) access to the EKS API server. Always true for production."
  type        = bool
  default     = true
}

variable "eks_cluster_log_types" {
  description = "EKS control-plane log types to ship to CloudWatch. POC: [api, audit]. Prod: all 5 types."
  type        = list(string)
  default     = ["api", "audit"]
}

# ---- ALB advanced ------------------------------------------------------

variable "alb_idle_timeout" {
  description = "ALB idle connection timeout in seconds. 60s for POC, 120s for UAT/Prod."
  type        = number
  default     = 60
}

variable "alb_enable_waf" {
  description = "Attach AWS WAFv2 WebACL (AWS Managed Rules + per-IP rate limiting) to the ALB."
  type        = bool
  default     = false
}

# ---- Database operational parameters ----------------------------------

variable "db_backup_retention_days" {
  description = "Automated backup retention in days for Aurora and RDS clusters. POC: 1. Prod: 30."
  type        = number
  default     = 1
}

variable "db_performance_insights_retention" {
  description = "Performance Insights data retention in days. 7 = free tier. 731 = 2 years (paid)."
  type        = number
  default     = 7
}

variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0,1,5,10,15,30,60). 1 = max granularity for production."
  type        = number
  default     = 60
}

variable "kms_deletion_window" {
  description = "Waiting period (days) before a KMS CMK is deleted after running terraform destroy (7-30)."
  type        = number
  default     = 7
}

variable "secret_recovery_window" {
  description = "Recovery window (days) before a Secrets Manager secret is permanently deleted after removal (7-30)."
  type        = number
  default     = 7
}

variable "aurora_autoscaling_max_replicas" {
  description = "Maximum number of Aurora read replicas for auto-scaling. POC: 1. Prod: 10."
  type        = number
  default     = 1
}
