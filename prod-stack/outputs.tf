###############################################################################
# prod-stack/outputs.tf
###############################################################################

# ---- EC2 -------------------------------------------------------------------
output "ec2_instance_id"    { value = module.ec2.instance_id }
output "ec2_public_ip"      { value = module.ec2.public_ip }
output "ssm_connect_command" {
  description = "Open an SSM session to the EC2 app server"
  value       = "aws ssm start-session --target ${module.ec2.instance_id} --region ${var.aws_region}"
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
output "debezium_plugin_arn"   { value = module.msk_connect.plugin_arn }
output "debezium_connector_arn"{ value = module.msk_connect.connector_arn }
