###############################################################################
# Root Outputs
###############################################################################

# ---- VPC -------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT GWs, Librechat EC2)"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs (EC2 workers, MSK)"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private DB subnet IDs (Aurora, RDS, ElastiCache)"
  value       = module.vpc.private_db_subnet_ids
}

# ---- MSK -------------------------------------------------------------------

output "msk_bootstrap_brokers_sasl_iam" {
  description = "MSK Serverless bootstrap broker endpoint (SASL/IAM — port 9098)"
  value       = module.msk.bootstrap_brokers_sasl_iam
  sensitive   = true
}

# ---- Aurora (Source / Primary DB) ------------------------------------------

output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint"
  value       = module.aurora.cluster_endpoint
  sensitive   = true
}

output "aurora_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = module.aurora.reader_endpoint
  sensitive   = true
}

# ---- RDS PostgreSQL (CDC Source + Sink DB) ----------------------------------

output "rds_cluster_endpoint" {
  description = "RDS PostgreSQL writer endpoint"
  value       = module.rds.cluster_endpoint
  sensitive   = true
}

output "rds_reader_endpoint" {
  description = "RDS PostgreSQL reader endpoint"
  value       = module.rds.reader_endpoint
  sensitive   = true
}

# ---- ElastiCache Redis -----------------------------------------------------

output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint (writes)"
  value       = module.elasticache.primary_endpoint_address
  sensitive   = true
}

output "redis_reader_endpoint" {
  description = "ElastiCache Redis reader endpoint (reads)"
  value       = module.elasticache.reader_endpoint_address
  sensitive   = true
}

# ---- EC2 Instances ---------------------------------------------------------

output "ec2_transaction_sim_id" {
  description = "Transaction Simulator EC2 instance ID"
  value       = module.ec2_transaction_sim.instance_id
}

output "ec2_transaction_sim_private_ip" {
  description = "Transaction Simulator private IP"
  value       = module.ec2_transaction_sim.private_ip
}

output "ec2_debezium_id" {
  description = "Debezium CDC EC2 instance ID"
  value       = module.ec2_debezium.instance_id
}

output "ec2_debezium_private_ip" {
  description = "Debezium CDC private IP"
  value       = module.ec2_debezium.private_ip
}

output "ec2_redis_sink_id" {
  description = "Redis Sink Consumer EC2 instance ID"
  value       = module.ec2_redis_sink.instance_id
}

output "ec2_postgres_sink_id" {
  description = "PostgreSQL Sink Consumer EC2 instance ID"
  value       = module.ec2_postgres_sink.instance_id
}

output "ec2_librechat_id" {
  description = "Librechat EC2 instance ID"
  value       = module.ec2_librechat.instance_id
}

output "ec2_librechat_public_ip" {
  description = "Librechat public IP — access the UI at http://<this>:3000"
  value       = module.ec2_librechat.public_ip
}

output "ssm_connect_commands" {
  description = "Ready-to-run SSM connect commands for each EC2 instance"
  value = {
    transaction_sim = "aws ssm start-session --target ${module.ec2_transaction_sim.instance_id} --region ${var.aws_region}"
    debezium        = "aws ssm start-session --target ${module.ec2_debezium.instance_id} --region ${var.aws_region}"
    redis_sink      = "aws ssm start-session --target ${module.ec2_redis_sink.instance_id} --region ${var.aws_region}"
    postgres_sink   = "aws ssm start-session --target ${module.ec2_postgres_sink.instance_id} --region ${var.aws_region}"
    librechat       = "aws ssm start-session --target ${module.ec2_librechat.instance_id} --region ${var.aws_region}"
  }
}
