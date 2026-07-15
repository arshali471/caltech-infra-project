###############################################################################
# prod-stack/outputs.tf
###############################################################################

# ---- VPC (only populated when create_vpc = true) ---------------------------
output "vpc_id"             { value = local.vpc_id }
output "public_subnet_ids"  { value = local.public_subnet_ids }
output "private_subnet_ids" { value = local.private_subnet_ids }
output "nat_gateway_eip"    { value = var.create_vpc ? module.vpc[0].nat_eip : null }

# ---- EC2 -------------------------------------------------------------------
output "ec2_instance_id"    { value = module.ec2.instance_id }
output "ec2_public_ip"      { value = module.ec2.public_ip }
output "ssm_connect_command" {
  description = "Open an SSM session to the EC2 app server"
  value       = "aws ssm start-session --target ${module.ec2.instance_id} --region ${var.aws_region}"
}

output "ec2_pg_sink_instance_id" { value = module.ec2_pg_sink.instance_id }
output "ec2_pg_sink_public_ip"   { value = module.ec2_pg_sink.public_ip }
output "ssm_connect_command_pg_sink" {
  description = "Open an SSM session to EC2 PG sink server"
  value       = "aws ssm start-session --target ${module.ec2_pg_sink.instance_id} --region ${var.aws_region}"
}

output "ec2_redis_sink_instance_id" { value = module.ec2_redis_sink.instance_id }
output "ec2_redis_sink_public_ip"   { value = module.ec2_redis_sink.public_ip }
output "ssm_connect_command_redis_sink" {
  description = "Open an SSM session to EC2 Redis sink server"
  value       = "aws ssm start-session --target ${module.ec2_redis_sink.instance_id} --region ${var.aws_region}"
}

# ---- MSK -------------------------------------------------------------------
output "msk_cluster_arn"      { value = module.msk.cluster_arn }
output "msk_bootstrap_brokers"{ value = module.msk.bootstrap_brokers }

# ---- Aurora Source ---------------------------------------------------------
output "aurora_source_endpoint"        { value = module.aurora_source.endpoint }
output "aurora_source_reader_endpoint" { value = module.aurora_source.reader_endpoint }
output "aurora_source_secret_arn"      { value = module.secrets.aurora_source_secret_arn }

# ---- Aurora Sink -----------------------------------------------------------
output "aurora_sink_endpoint"          { value = module.aurora_sink.endpoint }
output "aurora_sink_reader_endpoint"   { value = module.aurora_sink.reader_endpoint }
output "aurora_sink_secret_arn"        { value = module.secrets.aurora_sink_secret_arn }

# ---- ElastiCache Redis -----------------------------------------------------
output "redis_endpoint" { value = module.elasticache.endpoint_address }
output "redis_port"     { value = module.elasticache.endpoint_port }

# ---- S3 --------------------------------------------------------------------
output "s3_plugins_bucket"   { value = module.s3.plugins_bucket_name }
output "s3_data_lake_bucket" { value = module.s3.data_lake_bucket_name }
output "s3_logs_bucket"      { value = module.s3.logs_bucket_name }

# ---- MSK Connect -----------------------------------------------------------
output "debezium_plugin_arn" {
  description = "Custom plugin ARN (same plugin used by all 5 source connectors)"
  value       = module.msk_connect["1"].plugin_arn
}

output "debezium_connector_arns" {
  description = "ARN of each Debezium source connector, keyed by table suffix (1–5)"
  value       = { for k, m in module.msk_connect : k => m.connector_arn }
}

output "oracle_plugin_arn" {
  description = "Custom plugin ARN used by the Debezium Oracle source connector (null when disabled)"
  value       = one(module.msk_connect_oracle[*].plugin_arn)
}

output "oracle_connector_arn" {
  description = "ARN of the Debezium Oracle source connector (null when disabled)"
  value       = one(module.msk_connect_oracle[*].connector_arn)
}
