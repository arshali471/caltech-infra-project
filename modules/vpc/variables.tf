###############################################################################
# modules/vpc/variables.tf
###############################################################################

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets (one per AZ)"
  type        = list(string)
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private DB subnets (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (cost saving — not recommended for production HA)"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Days to retain VPC flow logs in CloudWatch"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
