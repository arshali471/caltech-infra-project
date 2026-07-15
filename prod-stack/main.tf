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
# Step 0 — VPC + Subnets (opt-in via var.create_vpc)
# When create_vpc = true, this module builds the network from scratch.
# When create_vpc = false, the existing vpc_id / *_subnet_ids variables are used.
###############################################################################

module "vpc" {
  count = var.create_vpc ? 1 : 0

  source = "./modules/vpc"
  name   = local.name

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway

  tags = var.tags
}

# ---- Network IDs picked from either the new module or existing vars ---------

locals {
  vpc_id                 = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
  public_subnet_ids      = var.create_vpc ? module.vpc[0].public_subnet_ids : var.public_subnet_ids
  private_subnet_ids     = var.create_vpc ? module.vpc[0].private_subnet_ids : var.private_subnet_ids
  msk_subnet_ids         = var.create_vpc ? module.vpc[0].private_subnet_ids : var.msk_subnet_ids
  elasticache_subnet_ids = var.create_vpc ? module.vpc[0].private_subnet_ids : var.elasticache_subnet_ids

  # MSK Connect needs predictable IP usage. Use dedicated subnets if specified,
  # otherwise fall back to private_subnet_ids.
  msk_connect_subnet_ids = length(var.msk_connect_subnet_ids) > 0 ? var.msk_connect_subnet_ids : local.private_subnet_ids

  # EC2 placement — private subnet for dev/non-prod (per MoM); public subnet
  # for current prod (existing VPC). SSM endpoints + NAT handle private access.
  ec2_subnet_id = var.ec2_in_private_subnet ? local.private_subnet_ids[0] : local.public_subnet_ids[0]

  # VPC endpoints (SSM interface ENIs) follow the same tier as EC2.
  vpc_endpoint_subnet_ids = var.ec2_in_private_subnet ? local.private_subnet_ids : local.public_subnet_ids
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
  vpc_id           = local.vpc_id
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
  vpc_id     = local.vpc_id
  aws_region = var.aws_region
  subnet_ids = local.vpc_endpoint_subnet_ids

  # Attach S3 gateway endpoint to BOTH route tables when create_vpc=true so
  # EC2 in private subnets (dev) can reach S3 privately while public-tier
  # callers (prod existing VPC, or NAT-side traffic) also benefit.
  s3_gateway_route_table_ids = var.create_vpc ? compact([
    module.vpc[0].public_route_table_id,
    module.vpc[0].private_route_table_id,
  ]) : tolist(data.aws_route_tables.public.ids)

  tags = var.tags
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

  subnet_ids            = local.msk_subnet_ids
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

  engine            = var.aurora_engine
  engine_version    = var.aurora_engine_version
  db_name           = var.aurora_source_db_name
  master_username   = var.aurora_source_master_username
  master_password   = module.secrets.aurora_source_password
  subnet_ids        = local.private_subnet_ids
  security_group_id = module.security_groups.aurora_source_sg_id
  kms_key_arn       = module.kms.aurora_key_arn
  min_acu           = var.aurora_source_min_acu
  max_acu           = var.aurora_source_max_acu

  backup_retention_period      = var.aurora_backup_retention_period
  preferred_backup_window      = var.aurora_preferred_backup_window
  preferred_maintenance_window = var.aurora_preferred_maintenance_window
  skip_final_snapshot          = var.aurora_skip_final_snapshot
  deletion_protection          = var.aurora_deletion_protection
  cloudwatch_logs_exports      = var.aurora_cloudwatch_logs_exports

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

  engine            = var.aurora_engine
  engine_version    = var.aurora_engine_version
  db_name           = var.aurora_sink_db_name
  master_username   = var.aurora_sink_master_username
  master_password   = module.secrets.aurora_sink_password
  subnet_ids        = local.private_subnet_ids
  security_group_id = module.security_groups.aurora_sink_sg_id
  kms_key_arn       = module.kms.aurora_key_arn
  min_acu           = var.aurora_sink_min_acu
  max_acu           = var.aurora_sink_max_acu

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
  subnet_ids          = local.elasticache_subnet_ids
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
  instance_type         = var.ec2_app_server_instance_type
  subnet_id             = local.ec2_subnet_id
  key_pair_name         = var.ec2_key_pair_name
  security_group_id     = module.security_groups.ec2_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
  root_volume_gb        = var.ec2_root_volume_gb
  root_volume_type      = var.ec2_volume_type
  ebs_kms_key_arn       = module.kms.ebs_key_arn
  // java_package          = var.java_package
  // msk_iam_auth_version  = var.msk_iam_auth_version
  tags = var.tags
}

module "ec2_pg_sink" {
  source = "./modules/ec2"
  name   = "${local.name}-pg-sink"

  ami_id                = var.ec2_ami_id
  instance_type         = var.ec2_instance_type
  subnet_id             = local.ec2_subnet_id
  key_pair_name         = var.ec2_key_pair_name
  security_group_id     = module.security_groups.ec2_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
  root_volume_gb        = var.ec2_root_volume_gb
  root_volume_type      = var.ec2_volume_type
  ebs_kms_key_arn       = module.kms.ebs_key_arn
  tags                  = var.tags
}

module "ec2_redis_sink" {
  source = "./modules/ec2"
  name   = "${local.name}-redis-sink"

  ami_id                = var.ec2_ami_id
  instance_type         = var.ec2_instance_type
  subnet_id             = local.ec2_subnet_id
  key_pair_name         = var.ec2_key_pair_name
  security_group_id     = module.security_groups.ec2_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
  root_volume_gb        = var.ec2_root_volume_gb
  root_volume_type      = var.ec2_volume_type
  ebs_kms_key_arn       = module.kms.ebs_key_arn
  tags                  = var.tags
}

###############################################################################
# Step 9 — MSK Connect + Debezium (Phase 4 — CDC Connectors)
# PREREQUISITE: Upload Debezium ZIP to s3://$(terraform output -raw s3_plugins_bucket)/plugins/
#
# FIVE source connectors — one per source table. Each has its own dedicated
# PostgreSQL replication slot + publication so CDC for each table is fully
# isolated and independently restartable.
#
#   Connector -1 → student_enrollment    (slot_1 / publication_1)
#   Connector -2 → student_lms           (slot_2 / publication_2)
#   Connector -3 → section_enrollments   (slot_3 / publication_3)
#   Connector -4 → student_attendance    (slot_4 / publication_4)
#   Connector -5 → student_term_log      (slot_5 / publication_5)
#
# All 5 connectors share the same custom plugin, bootstrap, role, and SMT.
# Defined as a single map iterated via for_each to keep the code DRY.
###############################################################################

locals {
  debezium_source_connectors = {
    "1" = "public.student_enrollment"
    "2" = "public.student_lms"
    "3" = "public.section_enrollments"
    "4" = "public.student_attendance"
    "5" = "public.student_term_log"
  }

  # Per-connector subnet override — empty since all 5 connectors now use the
  # same subnets (msk_connect_subnet_ids: new 64-IP subnet + 069 subnet for AZ).
  msk_connect_subnet_override = {}
}

module "msk_connect" {
  source = "./modules/msk_connect"

  for_each = local.debezium_source_connectors

  name                  = local.name
  connector_name_suffix = "debezium-postgres-source-connector-${each.key}"
  custom_plugin_name    = var.msk_connect_custom_plugin_name
  bootstrap_servers     = module.msk.bootstrap_brokers_iam
  msk_connect_sg_id     = module.security_groups.msk_connect_sg_id
  private_subnet_ids    = lookup(local.msk_connect_subnet_override, each.key, local.msk_connect_subnet_ids)
  msk_connect_role_arn  = module.iam.msk_connect_role_arn
  kafkaconnect_version  = var.kafkaconnect_version
  min_workers           = var.msk_connect_min_workers
  max_workers           = var.msk_connect_max_workers
  mcu_count             = var.msk_connect_mcu_count
  scale_in_cpu_pct      = var.msk_connect_scale_in_cpu_pct
  scale_out_cpu_pct     = var.msk_connect_scale_out_cpu_pct

  converter_schemas_enabled = false

  connector_configuration = {
    "connector.class"                        = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"                              = tostring(var.debezium_tasks_max)
    "database.hostname"                      = module.aurora_source.endpoint
    "database.port"                          = tostring(var.postgres_port)
    "database.user"                          = var.aurora_source_master_username
    "database.password"                      = module.secrets.aurora_source_password
    "database.dbname"                        = var.aurora_source_db_name
    "topic.prefix"                           = var.debezium_topic_prefix
    "plugin.name"                            = var.debezium_plugin_name
    "slot.name"                              = "${var.debezium_slot_name}_${each.key}"
    "slot.drop.on.stop"                      = "false"
    "publication.name"                       = "${var.debezium_publication_name}_${each.key}"
    "publication.autocreate.mode"            = "all_tables"
    "snapshot.mode"                          = var.debezium_snapshot_mode
    "schema.include.list"                    = var.debezium_schema_include_list
    "table.include.list"                     = each.value
    "heartbeat.interval.ms"                  = tostring(var.debezium_heartbeat_interval_ms)
    "decimal.handling.mode"                  = "double"
    "time.precision.mode"                    = "connect"
    "max.queue.size"                         = "200000"
    "max.batch.size"                         = "20000"
    "poll.interval.ms"                       = "100"
    "transforms"                             = "unwrap"
    "transforms.unwrap.type"                 = "io.debezium.transforms.ExtractNewRecordState"
    "transforms.unwrap.add.headers"          = "op,ts_ms,source.ts_ms,before.external_sourced_id,before.student_id,before.term_id,before.student_enrollment_id,before.section_id"
    "transforms.unwrap.drop.tombstones"      = "false"
    "transforms.unwrap.delete.handling.mode" = "drop"
    "key.converter"                          = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"           = "false"
    "value.converter"                        = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable"         = "false"
  }

  tags = var.tags
}

###############################################################################
# Step 9b — MSK Connect Oracle source connector
#
# Reads from an EXTERNAL Oracle database (not managed by this stack) over
# LogMiner. The MSK Connect SG allows all egress, so no SG change is needed —
# but the Oracle host must be routable from the MSK Connect worker subnets.
#
# TWO CONNECTOR IMPLEMENTATIONS, selected by var.oracle_connector_type:
#
#   "debezium"  → io.debezium.connector.oracle.OracleConnector
#                 Free/open source. Plugin ZIP from Maven Central (bundles
#                 ojdbc11); add aws-msk-iam-auth.jar for the schema-history
#                 client's IAM auth. Emits Debezium-shaped events + unwrap SMT.
#
#   "confluent" → io.confluent.connect.oracle.cdc.OracleCdcSourceConnector
#                 LICENSED. Plugin ZIP from Confluent Hub + orai18n.jar +
#                 aws-msk-iam-auth.jar. Needs var.oracle_confluent_license or it
#                 stops after a 30-day trial. Emits a DIFFERENT event shape —
#                 downstream sink consumers must be reworked to match.
#
# The two share almost no configuration surface, so each has its own complete
# config map below. var.oracle_connect_custom_plugin_name MUST point at a plugin
# whose ZIP actually contains the chosen connector class — the plugin name is
# only a label, and a mismatch fails at apply with "Failed to find any class
# that implements Connector".
#
# Toggled off entirely by var.enable_oracle_source_connector so envs without an
# Oracle source plan cleanly.
###############################################################################

locals {
  # Debezium's schema-history client is a separate Kafka client from the worker's
  # producer/consumer and does NOT inherit the cluster's IAM auth from MSK Connect.
  # Requires aws-msk-iam-auth on the plugin classpath to load IAMLoginModule.
  oracle_debezium_iam_auth = {
    for pair in setproduct(["producer", "consumer"], local.oracle_msk_iam_props) :
    "schema.history.internal.${pair[0]}.${pair[1][0]}" => pair[1][1]
  }

  # Confluent's connector opens two Kafka clients of its own — one for the license
  # topic, one to read back the redo-log topic — and neither inherits the cluster's
  # IAM auth either.
  oracle_confluent_iam_auth = {
    for pair in setproduct(["confluent.topic", "redo.log.consumer"], local.oracle_msk_iam_props) :
    "${pair[0]}.${pair[1][0]}" => pair[1][1]
  }

  oracle_msk_iam_props = [
    ["security.protocol", "SASL_SSL"],
    ["sasl.mechanism", "AWS_MSK_IAM"],
    ["sasl.jaas.config", "software.amazon.msk.auth.iam.IAMLoginModule required;"],
    ["sasl.client.callback.handler.class", "software.amazon.msk.auth.iam.IAMClientCallbackHandler"],
  ]

  # The PDB key must be absent (not empty) for a non-CDB Oracle database — and the
  # two connectors spell it differently.
  oracle_debezium_pdb  = var.oracle_pdb_name != "" ? { "database.pdb.name" = var.oracle_pdb_name } : {}
  oracle_confluent_pdb = var.oracle_pdb_name != "" ? { "oracle.pdb.name" = var.oracle_pdb_name } : {}

  oracle_converters = {
    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter.schemas.enable" = "false"
  }

  # Default class per connector type; var.oracle_connector_class overrides it.
  oracle_default_class = var.oracle_connector_type == "confluent" ? "io.confluent.connect.oracle.cdc.OracleCdcSourceConnector" : "io.debezium.connector.oracle.OracleConnector"
  oracle_class         = var.oracle_connector_class != "" ? var.oracle_connector_class : local.oracle_default_class

  oracle_debezium_config = merge(
    local.oracle_debezium_iam_auth,
    local.oracle_debezium_pdb,
    local.oracle_converters,
    {
      "connector.class"             = local.oracle_class
      "tasks.max"                   = tostring(var.oracle_tasks_max)
      "database.hostname"           = var.oracle_db_host
      "database.port"               = tostring(var.oracle_db_port)
      "database.user"               = var.oracle_db_user
      "database.password"           = var.oracle_db_password
      "database.dbname"             = var.oracle_db_name
      "database.connection.adapter" = var.oracle_connection_adapter
      "topic.prefix"                = var.oracle_topic_prefix
      "table.include.list"          = var.oracle_table_include_list
      "snapshot.mode"               = var.oracle_snapshot_mode
      "heartbeat.interval.ms"       = tostring(var.debezium_heartbeat_interval_ms)
      "decimal.handling.mode"       = "double"
      "time.precision.mode"         = "connect"
      "max.queue.size"              = "200000"
      "max.batch.size"              = "20000"
      "poll.interval.ms"            = "100"

      # Oracle DDL history — required by the Oracle connector, unlike Postgres.
      "schema.history.internal.kafka.bootstrap.servers" = module.msk.bootstrap_brokers_iam
      "schema.history.internal.kafka.topic"             = var.oracle_schema_history_topic

      "transforms"                             = "unwrap"
      "transforms.unwrap.type"                 = "io.debezium.transforms.ExtractNewRecordState"
      "transforms.unwrap.add.headers"          = "op,ts_ms,source.ts_ms,before.external_sourced_id,before.student_id,before.term_id,before.student_enrollment_id,before.section_id"
      "transforms.unwrap.drop.tombstones"      = "false"
      "transforms.unwrap.delete.handling.mode" = "drop"
    }
  )

  oracle_confluent_config = merge(
    local.oracle_confluent_iam_auth,
    local.oracle_confluent_pdb,
    local.oracle_converters,
    {
      "connector.class" = local.oracle_class
      "tasks.max"       = tostring(var.oracle_tasks_max)

      "oracle.server"   = var.oracle_db_host
      "oracle.port"     = tostring(var.oracle_db_port)
      "oracle.sid"      = var.oracle_db_name
      "oracle.username" = var.oracle_db_user
      "oracle.password" = var.oracle_db_password

      "table.inclusion.regex"    = var.oracle_table_inclusion_regex
      "start.from"               = var.oracle_start_from
      "emit.tombstone.on.delete" = tostring(var.oracle_emit_tombstone_on_delete)

      # $${...} escapes Terraform interpolation — these are Confluent's own
      # topic-name template variables, resolved by the connector at runtime.
      "table.topic.name.template" = "${var.oracle_topic_prefix}.$${schemaName}.$${tableName}"
      "redo.log.topic.name"       = "${var.oracle_topic_prefix}-redo-log"

      # The connector reads its own redo-log topic back to build table events, so
      # it needs the brokers explicitly whenever table.topic.name.template is set.
      "redo.log.consumer.bootstrap.servers" = module.msk.bootstrap_brokers_iam

      # Licensed connector — the license topic lives on the same MSK cluster.
      "confluent.topic.bootstrap.servers"  = module.msk.bootstrap_brokers_iam
      "confluent.topic.replication.factor" = tostring(var.msk_broker_count)
      "confluent.license"                  = var.oracle_confluent_license
    }
  )

  # ---- "custom" — the app team's supplied config, rendered verbatim ----------
  # LogMiner property set with oracle.* prefixes instead of Debezium's database.*
  # prefixes, no unwrap SMT, and schema.include.list scoped to the Oracle schema.
  # Kept separate from oracle_debezium_config so the known-working Debezium
  # property set stays available as a fallback.
  oracle_custom_config = merge(
    local.oracle_debezium_iam_auth,
    var.oracle_pdb_name != "" ? { "oracle.pdb.name" = var.oracle_pdb_name } : {},
    local.oracle_converters,
    {
      "connector.class"           = local.oracle_class
      "tasks.max"                 = tostring(var.oracle_tasks_max)
      "oracle.hostname"           = var.oracle_db_host
      "oracle.port"               = tostring(var.oracle_db_port)
      "oracle.user"               = var.oracle_db_user
      "oracle.password"           = var.oracle_db_password
      "oracle.dbname"             = var.oracle_db_name
      "oracle.connection.adapter" = var.oracle_connection_adapter
      "topic.prefix"              = var.oracle_topic_prefix
      "schema.include.list"       = var.oracle_schema_include_list
      "table.include.list"        = var.oracle_table_include_list
      "snapshot.mode"             = var.oracle_snapshot_mode
      "heartbeat.interval.ms"     = tostring(var.debezium_heartbeat_interval_ms)
      "decimal.handling.mode"     = "double"
      "max.queue.size"            = "100000"
      "max.batch.size"            = "20000"
      "poll.interval.ms"          = "100"

      "schema.history.internal.kafka.bootstrap.servers" = module.msk.bootstrap_brokers_iam
      "schema.history.internal.kafka.topic"             = var.oracle_schema_history_topic
    }
  )

  oracle_connector_configuration = {
    debezium  = local.oracle_debezium_config
    confluent = local.oracle_confluent_config
    custom    = local.oracle_custom_config
  }[var.oracle_connector_type]
}

module "msk_connect_oracle" {
  source = "./modules/msk_connect"

  count = var.enable_oracle_source_connector ? 1 : 0

  name                  = local.name
  connector_name_suffix = var.oracle_connector_name_suffix
  custom_plugin_name    = var.oracle_connect_custom_plugin_name
  bootstrap_servers     = module.msk.bootstrap_brokers_iam
  msk_connect_sg_id     = module.security_groups.msk_connect_sg_id
  private_subnet_ids    = local.msk_connect_subnet_ids
  msk_connect_role_arn  = module.iam.msk_connect_role_arn
  kafkaconnect_version  = var.kafkaconnect_version
  min_workers           = var.msk_connect_min_workers
  max_workers           = var.msk_connect_max_workers
  mcu_count             = var.msk_connect_mcu_count
  scale_in_cpu_pct      = var.msk_connect_scale_in_cpu_pct
  scale_out_cpu_pct     = var.msk_connect_scale_out_cpu_pct

  converter_schemas_enabled = false

  connector_configuration = local.oracle_connector_configuration

  tags = var.tags
}

