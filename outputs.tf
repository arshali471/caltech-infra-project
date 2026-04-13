###############################################################################
# Root Outputs
###############################################################################

# VPC
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs"
  value       = module.vpc.private_db_subnet_ids
}

# EKS
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "eks_cluster_version" {
  description = "Kubernetes version"
  value       = module.eks.cluster_version
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

# ALB
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

# MSK
output "msk_bootstrap_brokers_sasl_iam" {
  description = "MSK Serverless bootstrap brokers (SASL/IAM — the only supported auth method)"
  value       = module.msk.bootstrap_brokers_sasl_iam
  sensitive   = true
}

# Aurora
output "aurora_cluster_endpoint" {
  description = "Aurora cluster write endpoint"
  value       = module.aurora.cluster_endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Aurora cluster read endpoint"
  value       = module.aurora.reader_endpoint
  sensitive   = true
}

# RDS (Aurora Serverless v2 CDC source)
output "rds_cluster_endpoint" {
  description = "Aurora Serverless v2 CDC cluster writer endpoint"
  value       = module.rds.cluster_endpoint
  sensitive   = true
}

output "rds_reader_endpoint" {
  description = "Aurora Serverless v2 CDC cluster reader endpoint"
  value       = module.rds.reader_endpoint
  sensitive   = true
}

# Redis
output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint"
  value       = module.elasticache.primary_endpoint_address
  sensitive   = true
}

output "redis_reader_endpoint" {
  description = "ElastiCache Redis reader endpoint"
  value       = module.elasticache.reader_endpoint_address
  sensitive   = true
}
