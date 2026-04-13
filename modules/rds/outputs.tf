###############################################################################
# modules/rds/outputs.tf
###############################################################################

output "cluster_identifier" {
  description = "Aurora Serverless v2 CDC cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Aurora CDC cluster ARN"
  value       = aws_rds_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Aurora CDC cluster writer endpoint (host:port)"
  value       = aws_rds_cluster.this.endpoint
  sensitive   = true
}

output "reader_endpoint" {
  description = "Aurora CDC cluster reader endpoint (host:port)"
  value       = aws_rds_cluster.this.reader_endpoint
  sensitive   = true
}

output "cluster_port" {
  description = "Aurora CDC cluster port"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Name of the initial database"
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "Master DB username"
  value       = aws_rds_cluster.this.master_username
  sensitive   = true
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding master credentials"
  value       = aws_secretsmanager_secret.rds_master.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key for Aurora encryption"
  value       = aws_kms_key.rds.arn
}

