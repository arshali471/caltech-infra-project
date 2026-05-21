###############################################################################
# prod-stack/main.tf
#
# DEPLOYMENT ORDER — left to right matching the architecture diagram.
# Run each step, verify success, then move to the next.
#
# DEPLOYMENT ORDER — matches the client diagram left to right:
#   EC2 → Aurora Source → Debezium/CDC → MSK (Kafka) → Redis Sink + PG Sink
#
# ── PHASE 1: Foundation ──────────────────────────────────────────────────────
#   Step 1   terraform apply -target=module.kms
#   Step 2   terraform apply -target=module.security_groups
#   Step 3   terraform apply -target=module.s3
#   Step 4   terraform apply -target=module.secrets
#   Step 5   terraform apply -target=module.iam        ← uses msk_cluster_arn="*" initially
#
# ── PHASE 2: App Server (leftmost in diagram) ────────────────────────────────
#   Step 6   terraform apply -target=module.ec2
#            → Hand off: SSM access, instance ID
#
# ── PHASE 3: Source DB ───────────────────────────────────────────────────────
#   Step 7   terraform apply -target=module.aurora_source
#            → Hand off: Source DB endpoint + password (app team runs Txn Simulator)
#
# ── PHASE 4: CDC Pipeline (Debezium → MSK Connect → Kafka) ──────────────────
#   Step 8   terraform apply -target=module.msk          ← MSK Serverless (Kafka)
#            → Hand off: MSK broker endpoint
#   Step 9   # Upload Debezium ZIP to S3 first:
#            # aws s3 cp debezium-connector-postgres-*.Final-plugin.zip \
#            #   s3://$(terraform output -raw s3_plugins_bucket)/plugins/<filename> \
#            #   --profile caltect-account
#            terraform apply -target=module.msk_connect
#            → Hand off: Kafka topics live, CDC flowing from Aurora Source → MSK
#
# ── PHASE 5: Consumer Targets (right side of diagram) ────────────────────────
#   Step 10  terraform apply -target=module.elasticache  ← Redis Sink target
#            → Hand off: Redis endpoint + port
#   Step 11  terraform apply -target=module.aurora_sink  ← PostgreSQL Sink target
#            → Hand off: Sink DB endpoint + password
#
# ── PHASE 6: Final Pass ──────────────────────────────────────────────────────
#   Step 12  terraform apply
#            → Tightens IAM MSK policy from * to exact cluster ARN
#
###############################################################################

locals {
  name = "${var.project}-${var.environment}"
}

###############################################################################
# Step 1 — KMS
###############################################################################

module "kms" {
  source               = "./modules/kms"
  name                 = local.name
  deletion_window_days = var.kms_deletion_window_days
  tags                 = var.tags
}

###############################################################################
# Step 2 — Security Groups
###############################################################################

module "security_groups" {
  source           = "./modules/security_groups"
  name             = local.name
  vpc_id           = var.vpc_id
  msk_port         = var.msk_port
  msk_scram_port   = var.msk_scram_port
  postgres_port    = var.postgres_port
  redis_port       = var.redis_port
  ssh_allowed_cidr = var.ssh_allowed_cidr
  tags             = var.tags
}

###############################################################################
# Step 2b — VPC Endpoints (SSM — required for Session Manager without public IP)
###############################################################################

module "vpc_endpoints" {
  source     = "./modules/vpc_endpoints"
  name       = local.name
  vpc_id     = var.vpc_id
  aws_region = var.aws_region
  subnet_ids = var.public_subnet_ids
  tags       = var.tags
}

###############################################################################
# Step 3 — S3
###############################################################################

module "s3" {
  source      = "./modules/s3"
  name        = local.name
  kms_key_arn = module.kms.s3_key_arn

  data_lake_ia_transition_days      = var.data_lake_ia_transition_days
  data_lake_glacier_transition_days = var.data_lake_glacier_transition_days
  data_lake_noncurrent_expiry_days  = var.data_lake_noncurrent_expiry_days
  logs_expiry_days                  = var.logs_expiry_days
  logs_noncurrent_expiry_days       = var.logs_noncurrent_expiry_days

  tags = var.tags
}

###############################################################################
# Step 4 — Secrets Manager
###############################################################################

module "secrets" {
  source                        = "./modules/secrets"
  name                          = local.name
  kms_key_arn                   = module.kms.secrets_key_arn
  aurora_source_master_username = var.aurora_source_master_username
  aurora_sink_master_username   = var.aurora_sink_master_username
  secret_recovery_window_days   = var.secret_recovery_window_days
  password_length               = var.password_length
  tags                          = var.tags
}

###############################################################################
# Step 8 — MSK Serverless (Phase 4 — Kafka, separate step matching the diagram)
###############################################################################

module "msk" {
  source = "./modules/msk"
  name   = local.name

  subnet_ids            = var.msk_subnet_ids
  security_group_id     = module.security_groups.msk_sg_id
  kms_key_arn           = module.kms.secrets_key_arn
  kafka_version         = var.msk_kafka_version
  broker_count          = var.msk_broker_count
  broker_instance_type  = var.msk_broker_instance_type
  broker_volume_size_gb = var.msk_broker_volume_size_gb
  tags                  = var.tags
}

###############################################################################
# Step 5 — IAM (Foundation — msk_cluster_arn="*" until final terraform apply)
###############################################################################

module "iam" {
  source = "./modules/iam"
  name   = local.name

  aws_region      = var.aws_region
  account_id      = data.aws_caller_identity.current.account_id
  msk_cluster_arn = module.msk.cluster_arn

  s3_plugins_bucket_arn    = module.s3.plugins_bucket_arn
  s3_data_lake_bucket_arn  = module.s3.data_lake_bucket_arn
  s3_logs_bucket_arn       = module.s3.logs_bucket_arn
  s3_kms_key_arn           = module.kms.s3_key_arn
  secrets_kms_key_arn      = module.kms.secrets_key_arn
  aurora_source_secret_arn = module.secrets.aurora_source_secret_arn
  aurora_sink_secret_arn   = module.secrets.aurora_sink_secret_arn

  tags = var.tags
}

###############################################################################
# Step 7 — Aurora Source (Phase 3 — Source DB)
###############################################################################

module "aurora_source" {
  source = "./modules/aurora_source"
  name   = local.name

  engine         = var.aurora_engine
  engine_version = var.aurora_engine_version
  db_name        = var.aurora_source_db_name
  master_username = var.aurora_source_master_username
  master_password = module.secrets.aurora_source_password
  subnet_ids      = var.private_subnet_ids
  security_group_id = module.security_groups.aurora_source_sg_id
  kms_key_arn     = module.kms.aurora_key_arn
  min_acu         = var.aurora_source_min_acu
  max_acu         = var.aurora_source_max_acu

  backup_retention_period     = var.aurora_backup_retention_period
  preferred_backup_window     = var.aurora_preferred_backup_window
  preferred_maintenance_window = var.aurora_preferred_maintenance_window
  skip_final_snapshot         = var.aurora_skip_final_snapshot
  deletion_protection         = var.aurora_deletion_protection
  cloudwatch_logs_exports     = var.aurora_cloudwatch_logs_exports

  max_replication_slots = var.aurora_source_max_replication_slots
  max_wal_senders       = var.aurora_source_max_wal_senders
  wal_sender_timeout_ms = var.aurora_source_wal_sender_timeout_ms

  tags = var.tags
}

###############################################################################
# Step 11 — Aurora Sink (Phase 5 — PostgreSQL Sink Consumer Target)
###############################################################################

module "aurora_sink" {
  source = "./modules/aurora_sink"
  name   = local.name

  engine         = var.aurora_engine
  engine_version = var.aurora_engine_version
  db_name        = var.aurora_sink_db_name
  master_username = var.aurora_sink_master_username
  master_password = module.secrets.aurora_sink_password
  subnet_ids      = var.private_subnet_ids
  security_group_id = module.security_groups.aurora_sink_sg_id
  kms_key_arn     = module.kms.aurora_key_arn
  min_acu         = var.aurora_sink_min_acu
  max_acu         = var.aurora_sink_max_acu

  backup_retention_period      = var.aurora_backup_retention_period
  preferred_backup_window      = var.aurora_preferred_backup_window
  preferred_maintenance_window = var.aurora_preferred_maintenance_window
  skip_final_snapshot          = var.aurora_skip_final_snapshot
  deletion_protection          = var.aurora_deletion_protection
  cloudwatch_logs_exports      = var.aurora_cloudwatch_logs_exports

  tags = var.tags
}

###############################################################################
# Step 10 — ElastiCache Redis (Phase 5 — Redis Sink Consumer Target)
###############################################################################

module "elasticache" {
  source = "./modules/elasticache"
  name   = local.name

  engine              = var.elasticache_engine
  subnet_ids          = var.elasticache_subnet_ids
  security_group_id   = module.security_groups.elasticache_sg_id
  kms_key_arn         = module.kms.redis_key_arn
  min_data_storage_gb = var.redis_min_data_storage_gb
  max_data_storage_gb = var.redis_max_data_storage_gb
  min_ecpu_per_second = var.redis_min_ecpu_per_second
  max_ecpu_per_second = var.redis_max_ecpu_per_second
  tags                = var.tags
}

###############################################################################
# Step 6 — EC2 (Phase 2 — App Server, leftmost in diagram)
###############################################################################

module "ec2" {
  source = "./modules/ec2"
  name   = local.name

  ami_id                = var.ec2_ami_id
  instance_type         = var.ec2_instance_type
  subnet_id             = var.public_subnet_ids[0]
  key_pair_name         = var.ec2_key_pair_name
  security_group_id     = module.security_groups.ec2_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
  root_volume_gb        = var.ec2_root_volume_gb
  root_volume_type      = var.ec2_volume_type
  ebs_kms_key_arn       = module.kms.ebs_key_arn
  // java_package          = var.java_package
  // msk_iam_auth_version  = var.msk_iam_auth_version
  tags                  = var.tags
}

###############################################################################
# Step 9 — MSK Connect + Debezium (Phase 4 — CDC Connector)
# PREREQUISITE: Upload Debezium ZIP to s3://$(terraform output -raw s3_plugins_bucket)/plugins/
###############################################################################

module "msk_connect" {
  source = "./modules/msk_connect"
  name   = local.name

  bootstrap_servers      = module.msk.bootstrap_brokers_iam
  msk_connect_sg_id      = module.security_groups.msk_connect_sg_id
  private_subnet_ids     = var.private_subnet_ids
  debezium_plugin_s3_key = var.debezium_plugin_s3_key
  plugins_bucket_arn     = module.s3.plugins_bucket_arn
  plugins_bucket_name    = module.s3.plugins_bucket_name
  logs_bucket_name       = module.s3.logs_bucket_name
  msk_connect_role_arn   = module.iam.msk_connect_role_arn
  aurora_source_endpoint = module.aurora_source.endpoint
  aurora_source_db_name  = var.aurora_source_db_name
  aurora_source_username = var.aurora_source_master_username
  aurora_source_password = module.secrets.aurora_source_password

  kafkaconnect_version   = var.kafkaconnect_version
  min_workers            = var.msk_connect_min_workers
  max_workers            = var.msk_connect_max_workers
  mcu_count              = var.msk_connect_mcu_count
  scale_in_cpu_pct       = var.msk_connect_scale_in_cpu_pct
  scale_out_cpu_pct      = var.msk_connect_scale_out_cpu_pct

  snapshot_mode                = var.debezium_snapshot_mode
  logical_decoding_plugin_name = var.debezium_plugin_name
  replication_slot_name        = var.debezium_slot_name
  publication_name             = var.debezium_publication_name
  tasks_max                    = var.debezium_tasks_max
  heartbeat_interval_ms        = var.debezium_heartbeat_interval_ms
  database_port                = var.postgres_port

  tags = var.tags
}
