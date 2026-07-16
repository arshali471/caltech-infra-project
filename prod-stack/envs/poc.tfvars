###############################################################################
# prod-stack/terraform.tfvars
# All values are explicit — nothing is hardcoded in any module.
#
# TWO NETWORK MODES:
#   1. create_vpc = false  → Use the existing VPC (current default).
#                            Edit "Existing VPC" section below.
#   2. create_vpc = true   → Terraform builds a fresh VPC + subnets + IGW + NAT.
#                            Edit "New VPC (built by Terraform)" section below.
#   Only ONE section is consumed at a time — the other is harmless dead config.
###############################################################################

aws_profile = "default"
aws_region  = "us-west-2"
environment = "poc"
project     = "caltech"

# ============================================================================
# NETWORK MODE TOGGLE
# ============================================================================
# false → use existing VPC (vpc_id + *_subnet_ids below)
# true  → create a new VPC via module.vpc (vpc_cidr + AZ vars below)
create_vpc = false

# ---- New VPC (built by Terraform when create_vpc = true) -------------------
# These values are IGNORED when create_vpc = false.
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
enable_nat_gateway   = true

# ---- Existing VPC (used when create_vpc = false) ---------------------------
# Current production values for the existing Caltech VPC.
# These values are IGNORED when create_vpc = true.
vpc_id                 = "vpc-0ed44b92f11b73815"
public_subnet_ids      = ["subnet-038946a978f266b7d", "subnet-052b8a9527604c064"]
private_subnet_ids     = ["subnet-0afa40d43201113c7", "subnet-09fbbd79068ad5555"]
msk_subnet_ids         = ["subnet-0afa40d43201113c7", "subnet-09fbbd79068ad5555", "subnet-069266bf3b71d537e"]
elasticache_subnet_ids = ["subnet-09fbbd79068ad5555", "subnet-069266bf3b71d537e"]

# MSK Connect worker ENI placement.
# AWS REQUIRES 2–3 subnets per connector (single subnet is rejected with
# "The number of subnets per VPC must be between 2 and 3").
#
# Minimal 2-subnet config — biggest IP pool, lowest risk of exhaustion:
#   • subnet-0e525948c54e72b45 (NEW, 64 free IPs)  — primary worker placement
#   • subnet-069266bf3b71d537e (us-west-2c, 6 free IPs) — AZ partner
# Total: 70 IPs for 5 connectors × max 4 workers = 20 ENIs (3.5x headroom).
msk_connect_subnet_ids = [
  "subnet-0e525948c54e72b45", # NEW — 64 free IPs
  "subnet-069266bf3b71d537e", # us-west-2c — 6 free IPs (AZ partner)
]

# ---- Network ports ---------------------------------------------------------
msk_port       = 9098
msk_scram_port = 9096
postgres_port  = 5432
redis_port     = 6379

# ---- EC2 -------------------------------------------------------------------
ec2_ami_id                   = "ami-04486bbfa25728941"
ec2_key_pair_name            = "caltech-keypair"
ssh_allowed_cidr             = ["10.145.0.0/24"]
ec2_instance_type            = "t3.xlarge"   # used by ec2_pg_sink + ec2_redis_sink
ec2_app_server_instance_type = "m6i.2xlarge" # used by the primary app-server (txn simulator)
ec2_root_volume_gb           = 100
ec2_volume_type              = "gp3"
// java_package         = "java-17-amazon-corretto"
// msk_iam_auth_version = "1.1.9"

# ---- Aurora (shared) -------------------------------------------------------
aurora_engine                       = "aurora-postgresql"
aurora_engine_version               = "17.7"
aurora_backup_retention_period      = 7
aurora_preferred_backup_window      = "03:00-04:00"
aurora_preferred_maintenance_window = "sun:05:00-sun:06:00"
aurora_skip_final_snapshot          = false
aurora_deletion_protection          = true
aurora_cloudwatch_logs_exports      = ["postgresql"]

# ---- Aurora Source (CDC / Debezium) ----------------------------------------
aurora_source_db_name               = "sourcedb"
aurora_source_master_username       = "dbadmin"
aurora_source_min_acu               = 0.5
aurora_source_max_acu               = 16
aurora_source_max_replication_slots = 10
aurora_source_max_wal_senders       = 10
aurora_source_wal_sender_timeout_ms = 0

# ---- Aurora Sink (PostgreSQL consumer target) ------------------------------
aurora_sink_db_name         = "sinkdb"
aurora_sink_master_username = "dbadmin"
aurora_sink_min_acu         = 0.5
aurora_sink_max_acu         = 16

# ---- ElastiCache -----------------------------------------------------------
elasticache_engine        = "redis"
redis_min_data_storage_gb = 1
redis_max_data_storage_gb = 100
redis_min_ecpu_per_second = 1000
redis_max_ecpu_per_second = 500000

# ---- MSK Provisioned -------------------------------------------------------
msk_kafka_version         = "3.9.x"
msk_broker_count          = 3
msk_broker_instance_type  = "kafka.m5.2xlarge"
msk_broker_volume_size_gb = 1000

# ---- MSK Connect -----------------------------------------------------------
kafkaconnect_version           = "3.7.x"
debezium_plugin_s3_key         = "plugins/debezium-debezium-connector-postgresql-3.2.6-1.zip"
msk_connect_custom_plugin_name = "caltech-poc-debezium-postgresql-source-connector-plugin"
msk_connect_min_workers        = 2
msk_connect_max_workers        = 4
msk_connect_mcu_count          = 1
msk_connect_scale_in_cpu_pct   = 20
msk_connect_scale_out_cpu_pct  = 80

# ---- Debezium connector ----------------------------------------------------
debezium_snapshot_mode         = "initial"
debezium_plugin_name           = "pgoutput"
debezium_slot_name             = "dbz_students_slot" # connector 1 uses ${name}_1, connector 2 uses ${name}_2
debezium_publication_name      = "dbz_publication"   # connector 1 uses ${name}_1, connector 2 uses ${name}_2
debezium_topic_prefix          = "caltech_poc_10"
debezium_tasks_max             = 1
debezium_heartbeat_interval_ms = 30000
debezium_schema_include_list   = "public"
debezium_table_include_list    = "public.section_enrollments,public.student_attendance,public.student_enrollment,public.student_lms,public.student_term_log"

# ---- Oracle source connector (LogMiner) ------------------------------------
# Reads CDC from the external Oracle DB at oracle_db_host — NOT managed by this
# stack. The host must be routable from msk_connect_subnet_ids above.
#
# oracle_connector_type picks the implementation. It MUST match what is actually
# inside the plugin ZIP named below — the plugin name is only a label.
#
#   "debezium"  → plugin ZIP from Maven Central (debezium-connector-oracle,
#                 bundles ojdbc11) + aws-msk-iam-auth.jar.
#   "confluent" → plugin ZIP from Confluent Hub (kafka-connect-oracle-cdc)
#                 + orai18n.jar + aws-msk-iam-auth.jar, AND a license key below.
#                 Register it as a NEW plugin; do not reuse the Debezium one.
#
# Verify what is registered before flipping this:
#   aws kafkaconnect list-custom-plugins --region us-west-2 \
#     --query 'customPlugins[].{Name:name,File:latestRevision.location.s3Location.fileKey}'
enable_oracle_source_connector = true

# "custom" = the app team's supplied property set (oracle.* prefixes, no SMT).
# Switch to "debezium" for the known-working Debezium property set.
oracle_connector_type = "custom"

# Empty = use the class that matches oracle_connector_type. With type = "custom"
# / "debezium" that resolves to io.debezium.connector.oracle.OracleConnector,
# which is the ONLY class inside the caltech-poc-debezium-oracle-source-fplugin-fix
# plugin ZIP. Setting the Confluent class here fails at runtime with
# "Failed to find any class that implements Connector" because that class is not
# in the plugin — switch to a Confluent Hub plugin before using its class.
oracle_connector_class = ""

# Plugin name taken verbatim from the app team's config — "fplugin" is theirs,
# not a typo on our side. Must match the registered plugin EXACTLY or plan fails
# with "no matching MSK Connect Custom Plugin found".
oracle_connect_custom_plugin_name = "caltech-poc-debezium-oracle-source-fplugin-fix"

# New "schema-restricted" connector. Changing the suffix REPLACES the previous
# connector, log group, and worker config — expected, this is a new connector.
oracle_connector_name_suffix = "debezium-oracle-source-connector-schema-restricted"

# ---- Oracle worker capacity — FIXED provisioned, no autoscaling -------------
# Debezium Oracle is single-task (tasks.max = 1), so extra workers only provide
# failover, not throughput. Set to 2 if you want a standby worker; costs 1 more ENI.
oracle_worker_count = 1

oracle_db_host     = "10.115.6.11"
oracle_db_port     = 1920         # non-default listener port (Oracle default is 1521)
oracle_db_user     = "c##dbzuser" # common user — required when capturing from a CDB
oracle_db_password = "dbz"
oracle_db_name     = "EXETST1C" # CDB identifier (database.dbname / oracle.sid)
oracle_pdb_name    = "EXETEST1" # PDB name — set to "" for a non-CDB database

oracle_topic_prefix = "caltech_poc_oracle_test"
oracle_tasks_max    = 1

# ---- used when oracle_connector_type = "debezium" or "custom" ---------------
oracle_table_include_list   = "EXETER.SSS_AREAS"
oracle_connection_adapter   = "logminer"
oracle_schema_history_topic = "schemahistory.oracle1" # per the app team's schema-restricted config
oracle_snapshot_mode        = "initial"

# ---- used only when oracle_connector_type = "custom" ------------------------
# The schema-restricted config filters by table.include.list alone, so
# oracle_schema_include_list is intentionally not applied.
# slot.name / publication.name are PostgreSQL carry-overs, inert for Oracle.
oracle_slot_name        = "dbz_students_slot_1"
oracle_publication_name = "dbz_publication_1"

# Restrict schema-history DDL capture to the included table only.
oracle_store_only_captured_tables_ddl   = true
oracle_store_only_captured_database_ddl = true

# ---- used when oracle_connector_type = "confluent" --------------------------
# Fully-qualified <PDB>.<SCHEMA>.<TABLE>, dots escaped as [.] — NOT the same
# format as oracle_table_include_list above.
oracle_table_inclusion_regex    = "EXETEST1[.]EXETER[.]SSS_AREAS"
oracle_start_from               = "snapshot" # Confluent's equivalent of snapshot.mode = initial
oracle_emit_tombstone_on_delete = false
oracle_confluent_license        = "" # empty = 30-day trial, then the connector STOPS

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
  Environment = "poc"
}
