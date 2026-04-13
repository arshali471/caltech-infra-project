###############################################################################
# modules/msk/outputs.tf
###############################################################################

output "cluster_arn" {
  description = "MSK Serverless cluster ARN"
  value       = aws_msk_serverless_cluster.this.arn
}

output "cluster_name" {
  description = "MSK Serverless cluster name"
  value       = aws_msk_serverless_cluster.this.cluster_name
}

output "bootstrap_brokers_sasl_iam" {
  description = "MSK Serverless bootstrap brokers string (SASL/IAM — the only supported auth method)"
  value       = aws_msk_serverless_cluster.this.bootstrap_brokers_sasl_iam
  sensitive   = true
}
