###############################################################################
# DEV environment — us-east-2 (Ohio), same AWS account as prod
# Run: terraform init -reconfigure -backend-config=envs/dev.backend.hcl
#      terraform plan  -var-file=envs/dev.tfvars
#      terraform apply -var-file=envs/dev.tfvars
#
# Configuration mirrors POC (same sizing, same node counts). Only the items
# that MUST differ are changed:
#   • region          (us-east-2 vs us-west-2)
#   • VPC             (fresh 10.146.0.0/16 vs existing prod VPC)
#   • EC2 placement   (private subnets vs public — per MoM)
#   • AMI + key pair  (region-specific)
#   • Topic prefix    (caltech_dev_10 vs caltech_poc_10)
#   • Plugin names    (caltech-dev-* prefix)
#   • env label       (dev)
###############################################################################

aws_profile = "default"
aws_region  = "us-east-2"
environment = "dev"
project     = "caltech"

# ============================================================================
# NETWORK — create a fresh VPC in us-east-2 (no existing VPC there yet)
# Per MoM: no public subnets exposed for core services; outbound via NAT;
# inbound exposure (if needed later) goes through ALB / API Gateway.
# Public subnets are still created (required for NAT + future ALB), but no
# core service is placed in them.
#
# Private-only access pattern:
#   • EC2 instances live in PRIVATE subnets (ec2_in_private_subnet = true)
#   • Admin access  → SSM Session Manager via VPC Interface Endpoints
#                     (ssm, ssmmessages, ec2messages) — no SSH from internet
#   • Outbound      → NAT Gateway in public subnet (yum, pip, etc.)
#   • S3 traffic    → S3 Gateway endpoint attached to private route table
# ============================================================================
create_vpc            = true
vpc_cidr              = "10.146.0.0/16"
availability_zones    = ["us-east-2a", "us-east-2b", "us-east-2c"]
public_subnet_cidrs   = ["10.146.1.0/24", "10.146.2.0/24", "10.146.3.0/24"]
private_subnet_cidrs  = ["10.146.11.0/24", "10.146.12.0/24", "10.146.13.0/24"]
enable_nat_gateway    = true
ec2_in_private_subnet = true

# Existing-VPC vars are unused when create_vpc=true, but keep them set to []
# so the input validators don't complain.
vpc_id                 = ""
public_subnet_ids      = []
private_subnet_ids     = []
msk_subnet_ids         = []
elasticache_subnet_ids = []
msk_connect_subnet_ids = []   # falls back to module.vpc.private_subnet_ids

# ---- Network ports (same as POC) -------------------------------------------
msk_port       = 9098
msk_scram_port = 9096
postgres_port  = 5432
redis_port     = 6379

# ---- EC2 (mirrors POC) -----------------------------------------------------
# AMI: us-east-2 has DIFFERENT AMI IDs than us-west-2.
# Find a fresh Amazon Linux 2023 AMI with:
#   aws ec2 describe-images --owners amazon --region us-east-2 \
#     --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
#               "Name=state,Values=available" \
#     --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text
ec2_ami_id                   = "ami-0c80e2b6ccb9ad6d1"   # placeholder — replace with actual us-east-2 AMI before deploy
ec2_key_pair_name            = "caltech-dev-keypair"     # CREATE this in us-east-2 console before deploy
ssh_allowed_cidr             = ["10.146.0.0/16"]         # restrict to VPC CIDR
ec2_instance_type            = "t3.xlarge"               # mirrors POC — pg_sink + redis_sink
ec2_app_server_instance_type = "m6i.2xlarge"             # mirrors POC — primary app-server (txn simulator)
ec2_root_volume_gb           = 100                       # mirrors POC
ec2_volume_type              = "gp3"

# ---- Aurora (shared) — mirrors POC -----------------------------------------
aurora_engine                       = "aurora-postgresql"
aurora_engine_version               = "17.7"
aurora_backup_retention_period      = 7
aurora_preferred_backup_window      = "03:00-04:00"
aurora_preferred_maintenance_window = "sun:05:00-sun:06:00"
aurora_skip_final_snapshot          = false              # take a final snapshot before delete
aurora_deletion_protection          = true               # protect dev DB from accidental delete
aurora_cloudwatch_logs_exports      = ["postgresql"]

# ---- Aurora Source (CDC / Debezium) — mirrors POC --------------------------
aurora_source_db_name               = "sourcedb"
aurora_source_master_username       = "dbadmin"
aurora_source_min_acu               = 0.5
aurora_source_max_acu               = 16
aurora_source_max_replication_slots = 10
aurora_source_max_wal_senders       = 10
aurora_source_wal_sender_timeout_ms = 0

# ---- Aurora Source Limitless (variant) — mirrors POC -----------------------
aurora_limitless_engine_version     = "16.13-limitless"
aurora_limitless_min_acu            = 16
aurora_limitless_max_acu            = 32
aurora_limitless_compute_redundancy = 0

# ---- Aurora Sink (PostgreSQL consumer target) — mirrors POC ----------------
aurora_sink_db_name         = "sinkdb"
aurora_sink_master_username = "dbadmin"
aurora_sink_min_acu         = 0.5
aurora_sink_max_acu         = 16

# ---- ElastiCache — mirrors POC ---------------------------------------------
elasticache_engine        = "redis"
redis_min_data_storage_gb = 1
redis_max_data_storage_gb = 100
redis_min_ecpu_per_second = 1000
redis_max_ecpu_per_second = 500000

# ---- MSK Provisioned — mirrors POC -----------------------------------------
msk_kafka_version         = "3.9.x"
msk_broker_count          = 3
msk_broker_instance_type  = "kafka.m5.2xlarge"
msk_broker_volume_size_gb = 1000

# ---- MSK Connect — mirrors POC (dev-specific plugin names only) ------------
kafkaconnect_version           = "3.7.x"
debezium_plugin_s3_key         = "plugins/debezium-debezium-connector-postgresql-3.2.6-1.zip"
msk_connect_custom_plugin_name = "caltech-dev-debezium-postgresql-source-connector-plugin"
msk_connect_sink_plugin_name   = "caltech-dev-postgres-sink-connector-plugin"
sink_topics                    = "caltech_dev_10.public.student_enrollment"
sink_table_name_format         = "student_enrollment"
msk_connect_min_workers        = 2
msk_connect_max_workers        = 4
msk_connect_mcu_count          = 1
msk_connect_scale_in_cpu_pct   = 20
msk_connect_scale_out_cpu_pct  = 80

# ---- Debezium connector — mirrors POC (dev topic prefix only) --------------
debezium_snapshot_mode         = "initial"
debezium_plugin_name           = "pgoutput"
debezium_slot_name             = "dbz_students_slot"
debezium_publication_name      = "dbz_publication"
debezium_topic_prefix          = "caltech_dev_10"
debezium_tasks_max             = 1
debezium_heartbeat_interval_ms = 30000
debezium_schema_include_list   = "public"
debezium_table_include_list    = "public.section_enrollments,public.student_attendance,public.student_enrollment,public.student_lms,public.student_term_log"

# ---- S3 lifecycle — mirrors POC --------------------------------------------
data_lake_ia_transition_days      = 30
data_lake_glacier_transition_days = 90
data_lake_noncurrent_expiry_days  = 90
logs_expiry_days                  = 90
logs_noncurrent_expiry_days       = 30

# ---- KMS / Secrets — mirrors POC -------------------------------------------
kms_deletion_window_days    = 30
secret_recovery_window_days = 30
password_length             = 32

# ---- Tags ------------------------------------------------------------------
tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "caltech"
  Environment = "dev"
}
