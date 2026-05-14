###############################################################################
# prod-stack/terraform.tfvars
# All values are explicit — nothing is hardcoded in any module.
# Update vpc_id / subnet_ids before running terraform apply.
###############################################################################

aws_profile = "caltect-account"
aws_region  = "us-west-2"
environment = "prod"
project     = "caltech"

# ---- Existing VPC ----------------------------------------------------------
vpc_id             = "vpc-XXXXXXXXXXXXXXXXX"
public_subnet_ids  = ["subnet-XXXXXXXXXXXXXXXXX", "subnet-XXXXXXXXXXXXXXXXX"]
private_subnet_ids = ["subnet-XXXXXXXXXXXXXXXXX", "subnet-XXXXXXXXXXXXXXXXX"]

# ---- Network ports ---------------------------------------------------------
msk_port      = 9098
postgres_port = 5432
redis_port    = 6379

# ---- EC2 -------------------------------------------------------------------
ec2_ami_id           = "ami-XXXXXXXXXXXXXXXXX"
ec2_instance_type    = "t3.large"
ec2_root_volume_gb   = 50
ec2_volume_type      = "gp3"
java_package         = "java-17-amazon-corretto"
msk_iam_auth_version = "1.1.9"

# ---- Aurora (shared) -------------------------------------------------------
aurora_engine                       = "aurora-postgresql"
aurora_engine_version               = "16.3"
aurora_backup_retention_period      = 7
aurora_preferred_backup_window      = "03:00-04:00"
aurora_preferred_maintenance_window = "sun:05:00-sun:06:00"
aurora_skip_final_snapshot          = false
aurora_deletion_protection          = true
aurora_cloudwatch_logs_exports      = ["postgresql"]

# ---- Aurora Source (CDC / Debezium) ----------------------------------------
aurora_source_db_name                = "sourcedb"
aurora_source_master_username        = "dbadmin"
aurora_source_min_acu                = 0.5
aurora_source_max_acu                = 16
aurora_source_max_replication_slots  = 10
aurora_source_max_wal_senders        = 10
aurora_source_wal_sender_timeout_ms  = 0

# ---- Aurora Sink (PostgreSQL consumer target) ------------------------------
aurora_sink_db_name           = "sinkdb"
aurora_sink_master_username   = "dbadmin"
aurora_sink_min_acu           = 0.5
aurora_sink_max_acu           = 16

# ---- ElastiCache -----------------------------------------------------------
elasticache_engine        = "redis"
redis_min_data_storage_gb = 1
redis_max_data_storage_gb = 100
redis_min_ecpu_per_second = 1000
redis_max_ecpu_per_second = 500000

# ---- MSK Connect -----------------------------------------------------------
kafkaconnect_version           = "2.7.1"
debezium_plugin_s3_key         = "plugins/debezium-connector-postgres-2.5.0.Final-plugin.zip"
msk_connect_min_workers        = 1
msk_connect_max_workers        = 2
msk_connect_mcu_count          = 1
msk_connect_scale_in_cpu_pct   = 20
msk_connect_scale_out_cpu_pct  = 80

# ---- Debezium connector ----------------------------------------------------
debezium_snapshot_mode         = "initial"
debezium_plugin_name           = "pgoutput"
debezium_slot_name             = "debezium_slot"
debezium_publication_name      = "debezium_pub"
debezium_tasks_max             = 1
debezium_heartbeat_interval_ms = 30000

# ---- S3 lifecycle ----------------------------------------------------------
data_lake_ia_transition_days      = 30
data_lake_glacier_transition_days = 90
data_lake_noncurrent_expiry_days  = 90
logs_expiry_days                  = 90
logs_noncurrent_expiry_days       = 30

# ---- KMS / Secrets ---------------------------------------------------------
kms_deletion_window_days    = 30
secret_recovery_window_days = 30
password_length             = 32

# ---- Tags ------------------------------------------------------------------
tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "caltech"
  Environment = "prod"
}
