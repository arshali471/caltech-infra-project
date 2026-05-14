###############################################################################
# test-stack/outputs.tf
###############################################################################

output "vpc_id" {
  description = "Test VPC ID"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (MSK + ElastiCache ENIs)"
  value       = aws_subnet.private[*].id
}

# ---- MSK (Kafka) ------------------------------------------------------------

output "msk_cluster_name" {
  description = "MSK Serverless cluster name"
  value       = module.msk.cluster_name
}

output "msk_cluster_arn" {
  description = "MSK Serverless cluster ARN"
  value       = module.msk.cluster_arn
}

output "msk_bootstrap_brokers_sasl_iam" {
  description = "MSK bootstrap broker string for SASL/IAM clients (use in kafka CLI --bootstrap-server)"
  value       = module.msk.bootstrap_brokers_sasl_iam
  sensitive   = true
}

# ---- ElastiCache Redis ------------------------------------------------------

output "redis_primary_endpoint" {
  description = "Redis primary endpoint for writes (redis-cli -h <this> -p 6379 --tls)"
  value       = module.elasticache.primary_endpoint_address
  sensitive   = true
}

output "redis_reader_endpoint" {
  description = "Redis reader endpoint for reads"
  value       = module.elasticache.reader_endpoint_address
  sensitive   = true
}

output "redis_port" {
  description = "Redis port (always 6379 for ElastiCache Serverless)"
  value       = module.elasticache.endpoint_port
}

# ---- Bastion ----------------------------------------------------------------

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID — use with: aws ssm start-session --target <this>"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Bastion public IP (informational — connect via SSM, not SSH)"
  value       = aws_instance.bastion.public_ip
}

output "ssm_connect_command" {
  description = "Ready-to-run SSM connect command for the bastion"
  value       = "aws ssm start-session --target ${aws_instance.bastion.id} --region ${data.aws_region.current.name}"
}
