variable "aws_region" {
  description = "AWS region for all test resources"
  type        = string
  default     = "us-west-1"
}

variable "project" {
  description = "Project slug used in resource names"
  type        = string
  default     = "cultech"
}

# ---- Networking -------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR block — must not overlap with the main project (10.0.0.0/16)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs — MSK Serverless requires subnets in at least 2 AZs"
  type        = list(string)
  default     = ["us-west-1a", "us-west-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnets for NAT Gateway and bastion instance"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnets for MSK and ElastiCache ENIs"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}

# ---- ElastiCache Redis -------------------------------------------------------

variable "redis_max_data_storage_gb" {
  description = "Max ElastiCache Serverless storage in GB"
  type        = number
  default     = 10
}

variable "redis_min_data_storage_gb" {
  description = "Min ElastiCache Serverless storage in GB"
  type        = number
  default     = 1
}

variable "redis_max_ecpu_per_second" {
  description = "Max ECPU/s for ElastiCache Serverless"
  type        = number
  default     = 10000
}

variable "redis_min_ecpu_per_second" {
  description = "Min ECPU/s for ElastiCache Serverless"
  type        = number
  default     = 1000
}

# ---- Bastion EC2 ------------------------------------------------------------

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

# ---- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged onto all resources"
  type        = map(string)
  default = {
    Owner      = "platform-team"
    CostCenter = "engineering"
    Purpose    = "testing"
  }
}
