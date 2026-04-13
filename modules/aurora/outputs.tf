###############################################################################
# modules/aurora/outputs.tf
###############################################################################

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.this.cluster_identifier
}

output "cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Aurora writer endpoint (for writes)"
  value       = aws_rds_cluster.this.endpoint
  sensitive   = true
}

output "reader_endpoint" {
  description = "Aurora reader endpoint (for reads)"
  value       = aws_rds_cluster.this.reader_endpoint
  sensitive   = true
}

output "cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "Name of the initial database"
  value       = aws_rds_cluster.this.database_name
}

output "master_username" {
  description = "Master username"
  value       = aws_rds_cluster.this.master_username
  sensitive   = true
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding master credentials"
  value       = aws_secretsmanager_secret.aurora_master.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key for Aurora encryption"
  value       = aws_kms_key.aurora.arn
}

output "instance_ids" {
  description = "List of Aurora instance identifiers"
  value       = aws_rds_cluster_instance.this[*].identifier
}
