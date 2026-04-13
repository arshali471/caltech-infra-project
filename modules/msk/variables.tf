###############################################################################
# modules/msk/variables.tf
# MSK Serverless — all broker scaling, storage, replication, and encryption
# are fully managed by AWS. Only cluster identity, VPC placement, and
# IAM authentication are configurable.
###############################################################################

variable "cluster_name" {
  description = "Name for the MSK Serverless cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for broker ENI placement (min 2, one per AZ)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for the MSK Serverless cluster"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
