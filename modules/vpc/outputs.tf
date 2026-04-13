###############################################################################
# modules/vpc/outputs.tf
###############################################################################

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "List of private app subnet IDs"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "List of private DB subnet IDs"
  value       = aws_subnet.private_db[*].id
}

output "db_subnet_group_name" {
  description = "Name of the RDS/Aurora DB subnet group"
  value       = aws_db_subnet_group.this.name
}

output "cache_subnet_group_name" {
  description = "Name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.this.name
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

# Security Groups

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "eks_cluster_security_group_id" {
  description = "ID of the EKS cluster security group"
  value       = aws_security_group.eks_cluster.id
}

output "eks_pods_security_group_id" {
  description = "ID of the EKS Fargate pods security group (Security Groups for Pods)"
  value       = aws_security_group.eks_pods.id
}

output "msk_security_group_id" {
  description = "ID of the MSK security group"
  value       = aws_security_group.msk.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}

output "elasticache_security_group_id" {
  description = "ID of the ElastiCache security group"
  value       = aws_security_group.elasticache.id
}
