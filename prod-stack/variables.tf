###############################################################################
# prod-stack/variables.tf — all inputs, no hardcoded values
###############################################################################

# ---- Project identity -------------------------------------------------------

variable "aws_profile" {
  description = "AWS CLI profile name to use for all operations (leave empty to use env vars or instance role)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment label (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project slug (lowercase, no spaces) — used as resource name prefix"
  type        = string
  default     = "caltech"
}

# ---- VPC --------------------------------------------------------------------
# Two modes:
#   create_vpc = true   → module.vpc builds a fresh VPC (uses vpc_cidr + AZ vars)
#   create_vpc = false  → use the existing VPC ID + subnet IDs below
# ----------------------------------------------------------------------------

variable "create_vpc" {
  description = "If true, Terraform creates a new VPC + subnets via module.vpc. If false, uses the existing vpc_id and *_subnet_ids variables."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC (only used when create_vpc = true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into when create_vpc = true (one subnet per AZ)"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs when create_vpc = true (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs when create_vpc = true (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway for private subnets (only used when create_vpc = true)"
  type        = bool
  default     = true
}

# ---- Existing VPC (used when create_vpc = false) ----------------------------

variable "vpc_id" {
  description = "ID of the existing VPC to deploy into (ignored when create_vpc = true)"
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (ignored when create_vpc = true)"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (ignored when create_vpc = true)"
  type        = list(string)
  default     = []
}

variable "msk_subnet_ids" {
  description = "MSK broker subnet IDs in 3 AZs (ignored when create_vpc = true — module.vpc subnets are used)"
  type        = list(string)
  default     = []
}

variable "elasticache_subnet_ids" {
  description = "ElastiCache subnet IDs (ignored when create_vpc = true — module.vpc private subnets are used)"
  type        = list(string)
  default     = []
}

variable "msk_connect_subnet_ids" {
  description = "Subnets for MSK Connect worker ENIs. Pick subnets with sufficient free IPs (each worker = 1 ENI). Falls back to private_subnet_ids if empty."
  type        = list(string)
  default     = []
}

variable "ec2_in_private_subnet" {
  description = "If true, all EC2 instances are placed in private subnets (no public IP, SSM-only admin access, outbound internet via NAT). Set true for dev/non-prod per MoM 'no public subnets for core services'."
  type        = bool
  default     = false
}

# ---- Network ports ----------------------------------------------------------

variable "msk_port" {
  description = "MSK IAM broker port (used by MSK Connect)"
  type        = number
  default     = 9098
}

variable "msk_scram_port" {
  description = "MSK SASL/SCRAM broker port (used by app clients)"
  type        = number
  default     = 9096
}

variable "postgres_port" {
  description = "PostgreSQL port for Aurora clusters"
  type        = number
  default     = 5432
}

variable "redis_port" {
  description = "Redis port for ElastiCache"
  type        = number
  default     = 6379
}

# ---- EC2 --------------------------------------------------------------------

variable "ec2_instance_type" {
  description = "EC2 instance type used by the sink consumer servers (pg_sink, redis_sink)"
  type        = string
  default     = "t3.large"
}

variable "ec2_app_server_instance_type" {
  description = "EC2 instance type for the primary application server (transaction simulator) — typically larger than the sink consumers"
  type        = string
  default     = "m6i.2xlarge"
}

variable "ec2_root_volume_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 50
}

variable "ec2_volume_type" {
  description = "EBS volume type (gp3, gp2, io1, io2)"
  type        = string
  default     = "gp3"
}

variable "ec2_ami_id" {
  description = "AMI ID for the EC2 instance (e.g. ami-0abcdef1234567890)"
  type        = string
}

variable "ec2_key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access to the app server"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDRs allowed to SSH into the EC2 instance (restrict to your office/VPN IPs in production)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "java_package" {
  description = "Java package name to install (e.g. java-17-amazon-corretto, java-21-amazon-corretto)"
  type        = string
  default     = "java-17-amazon-corretto"
}

variable "msk_iam_auth_version" {
  description = "Version of the aws-msk-iam-auth JAR to install on EC2"
  type        = string
  default     = "1.1.9"
}

# ---- Aurora (shared settings for both clusters) ----------------------------

variable "aurora_engine" {
  description = "Aurora engine (aurora-postgresql or aurora-mysql)"
  type        = string
  default     = "aurora-postgresql"
}

variable "aurora_engine_version" {
  description = "Aurora engine version — major version drives parameter group family"
  type        = string
  default     = "16.3"
}

variable "aurora_backup_retention_period" {
  description = "Automated backup retention in days (1-35)"
  type        = number
  default     = 7
}

variable "aurora_preferred_backup_window" {
  description = "Daily time range for automated backups (UTC, hh:mm-hh:mm)"
  type        = string
  default     = "03:00-04:00"
}

variable "aurora_preferred_maintenance_window" {
  description = "Weekly maintenance window (ddd:hh:mm-ddd:hh:mm)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "aurora_skip_final_snapshot" {
  description = "Skip final snapshot on cluster deletion (set true for dev/test)"
  type        = bool
  default     = false
}

variable "aurora_deletion_protection" {
  description = "Enable deletion protection on Aurora clusters"
  type        = bool
  default     = true
}

variable "aurora_cloudwatch_logs_exports" {
  description = "List of Aurora log types to export to CloudWatch"
  type        = list(string)
  default     = ["postgresql"]
}

# ---- Aurora Source (CDC / Debezium source) ----------------------------------

variable "aurora_source_db_name" {
  description = "Database name for Aurora source cluster"
  type        = string
  default     = "sourcedb"
}

variable "aurora_source_master_username" {
  description = "Master username for Aurora source cluster"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "aurora_source_min_acu" {
  description = "Minimum Aurora Capacity Units for source cluster"
  type        = number
  default     = 0.5
}

variable "aurora_source_max_acu" {
  description = "Maximum Aurora Capacity Units for source cluster"
  type        = number
  default     = 16
}

variable "aurora_source_max_replication_slots" {
  description = "max_replication_slots parameter for Debezium CDC"
  type        = number
  default     = 10
}

variable "aurora_source_max_wal_senders" {
  description = "max_wal_senders parameter for Debezium CDC"
  type        = number
  default     = 10
}

variable "aurora_source_wal_sender_timeout_ms" {
  description = "wal_sender_timeout in ms (0 = disabled)"
  type        = number
  default     = 0
}

# ---- Aurora Sink (PostgreSQL consumer target) --------------------------------

variable "aurora_sink_db_name" {
  description = "Database name for Aurora sink cluster"
  type        = string
  default     = "sinkdb"
}

variable "aurora_sink_master_username" {
  description = "Master username for Aurora sink cluster"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "aurora_sink_min_acu" {
  description = "Minimum Aurora Capacity Units for sink cluster"
  type        = number
  default     = 0.5
}

variable "aurora_sink_max_acu" {
  description = "Maximum Aurora Capacity Units for sink cluster"
  type        = number
  default     = 16
}

# ---- ElastiCache Redis ------------------------------------------------------

variable "elasticache_engine" {
  description = "ElastiCache Serverless engine (redis or valkey)"
  type        = string
  default     = "redis"
}

variable "redis_min_data_storage_gb" {
  description = "Minimum data storage in GB"
  type        = number
  default     = 1
}

variable "redis_max_data_storage_gb" {
  description = "Maximum data storage in GB"
  type        = number
  default     = 100
}

variable "redis_min_ecpu_per_second" {
  description = "Minimum ECPU per second"
  type        = number
  default     = 1000
}

variable "redis_max_ecpu_per_second" {
  description = "Maximum ECPU per second"
  type        = number
  default     = 500000
}

# ---- MSK Provisioned --------------------------------------------------------

variable "msk_kafka_version" {
  description = "Apache Kafka version for MSK Provisioned cluster"
  type        = string
  default     = "3.9.0"
}

variable "msk_broker_count" {
  description = "Number of MSK broker nodes (must equal number of private subnets)"
  type        = number
  default     = 3
}

variable "msk_broker_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m5.2xlarge"
}

variable "msk_broker_volume_size_gb" {
  description = "EBS storage per broker in GB"
  type        = number
  default     = 250
}

# ---- MSK Connect + Debezium -------------------------------------------------

variable "kafkaconnect_version" {
  description = "Kafka Connect version for MSK Connect workers"
  type        = string
  default     = "2.7.1"
}

variable "debezium_plugin_s3_key" {
  description = "S3 key of the Debezium connector ZIP in the plugins bucket"
  type        = string
  default     = "plugins/debezium-connector-postgres-2.5.0.Final-plugin.zip"
}

variable "msk_connect_custom_plugin_name" {
  description = "Name of the existing MSK Connect custom plugin created by the app team (source/Debezium)"
  type        = string
}

variable "msk_connect_min_workers" {
  description = "Minimum MSK Connect worker count"
  type        = number
  default     = 1
}

variable "msk_connect_max_workers" {
  description = "Maximum MSK Connect worker count"
  type        = number
  default     = 2
}

variable "msk_connect_mcu_count" {
  description = "MCU count per MSK Connect worker"
  type        = number
  default     = 1
}

variable "msk_connect_scale_in_cpu_pct" {
  description = "CPU % threshold for scaling in MSK Connect workers"
  type        = number
  default     = 20
}

variable "msk_connect_scale_out_cpu_pct" {
  description = "CPU % threshold for scaling out MSK Connect workers"
  type        = number
  default     = 80
}

variable "debezium_snapshot_mode" {
  description = "Debezium snapshot mode (initial, never, always, exported)"
  type        = string
  default     = "initial"
}

variable "debezium_plugin_name" {
  description = "Logical decoding plugin (pgoutput or decoderbufs)"
  type        = string
  default     = "pgoutput"
}

variable "debezium_slot_name" {
  description = "PostgreSQL replication slot name"
  type        = string
  default     = "dbz_students_slot"
}

variable "debezium_publication_name" {
  description = "PostgreSQL publication name"
  type        = string
  default     = "dbz_publication"
}

variable "debezium_topic_prefix" {
  description = "Kafka topic prefix for Debezium events"
  type        = string
  default     = "students_poc_10"
}

variable "debezium_schema_include_list" {
  description = "PostgreSQL schema(s) to include in CDC"
  type        = string
  default     = "public"
}

variable "debezium_table_include_list" {
  description = "Comma-separated list of tables to capture (schema.table format)"
  type        = string
  default     = "public.section_enrollments,public.student_attendance,public.student_enrollment,public.student_lms,public.student_term_log"
}

variable "debezium_tasks_max" {
  description = "Maximum number of Debezium connector tasks"
  type        = number
  default     = 1
}

variable "debezium_heartbeat_interval_ms" {
  description = "Debezium heartbeat interval in milliseconds"
  type        = number
  default     = 30000
}

# ---- Oracle source connector (LogMiner) -------------------------------------
# Captures CDC from an external Oracle database reachable from the MSK Connect
# worker subnets. Disabled by default so envs without an Oracle source
# (e.g. dev) plan cleanly with no extra config.
#
# Supports EITHER the Debezium or the Confluent Oracle connector — see
# var.oracle_connector_type. Variables below are grouped as shared / debezium-only
# / confluent-only; the unused group is harmless dead config.

variable "enable_oracle_source_connector" {
  description = "Create the Oracle source connector"
  type        = bool
  default     = false
}

variable "oracle_connector_type" {
  description = <<-DESC
    Which Oracle PROPERTY SET to render (var.oracle_connector_class sets the class):
      "debezium"  — Debezium's database.* properties + unwrap SMT (known-working)
      "confluent" — Confluent's oracle.server / table.inclusion.regex / start.from
      "custom"    — the app team's supplied oracle.* property set
    These share almost no properties and emit different event shapes.
    var.oracle_connect_custom_plugin_name must point at a plugin ZIP containing
    the connector class in use, or apply fails with "Failed to find any class
    that implements Connector".
  DESC
  type        = string
  default     = "debezium"

  validation {
    condition     = contains(["debezium", "confluent", "custom"], var.oracle_connector_type)
    error_message = "oracle_connector_type must be one of: debezium, confluent, custom."
  }
}

variable "oracle_connector_class" {
  description = <<-DESC
    Overrides connector.class independently of var.oracle_connector_type, which
    still selects the PROPERTY SET. Empty = use the class matching the type.
    Set this only to pair a class with the other type's properties — the plugin
    ZIP must still contain the class, and the class must accept the properties.
  DESC
  type        = string
  default     = ""
}

variable "oracle_connect_custom_plugin_name" {
  description = "Name of the existing MSK Connect custom plugin. Its ZIP must contain the connector class implied by var.oracle_connector_type — the name itself is only a label"
  type        = string
  default     = ""
}

variable "oracle_connector_name_suffix" {
  description = "Appended to <project>-<env> to form the connector name. Changing this REPLACES the connector, its worker config, and its log group"
  type        = string
  default     = "oracle-source-connector"
}

variable "oracle_db_host" {
  description = "Oracle database hostname or IP reachable from the MSK Connect worker subnets"
  type        = string
  default     = ""
}

variable "oracle_db_port" {
  description = "Oracle listener port"
  type        = number
  default     = 1521
}

variable "oracle_db_user" {
  description = "Oracle CDC user (common user, e.g. c##dbzuser, when connecting to a CDB)"
  type        = string
  default     = ""
}

variable "oracle_db_password" {
  description = "Password for var.oracle_db_user"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oracle_db_name" {
  description = "Oracle SID — the CDB (container database) identifier. Maps to oracle.sid"
  type        = string
  default     = ""
}

variable "oracle_pdb_name" {
  description = "Oracle PDB (pluggable database) name; leave empty for a non-CDB database"
  type        = string
  default     = ""
}

variable "oracle_topic_prefix" {
  description = "Kafka topic prefix for Oracle CDC events. Table topics become <prefix>.<schema>.<table>; for confluent, the redo log topic becomes <prefix>-redo-log"
  type        = string
  default     = ""
}

# ---- Oracle: debezium-only --------------------------------------------------

variable "oracle_connection_adapter" {
  description = "[debezium] Capture adapter (logminer or xstream)"
  type        = string
  default     = "logminer"

  validation {
    condition     = contains(["logminer", "xstream"], var.oracle_connection_adapter)
    error_message = "oracle_connection_adapter must be either \"logminer\" or \"xstream\"."
  }
}

variable "oracle_table_include_list" {
  description = "[debezium] Comma-separated tables to capture, SCHEMA.TABLE form (uppercase). Note this is NOT the same format as var.oracle_table_inclusion_regex"
  type        = string
  default     = ""
}

variable "oracle_schema_history_topic" {
  description = "[debezium/custom] Internal Kafka topic where the connector stores DDL schema history"
  type        = string
  default     = "schemahistory.oracle"
}

variable "oracle_schema_include_list" {
  description = "[custom] Schema(s) to include in CDC"
  type        = string
  default     = ""
}

variable "oracle_slot_name" {
  description = "[custom] PostgreSQL replication slot name. Carried over from the app team's Postgres config; inert for an Oracle source"
  type        = string
  default     = ""
}

variable "oracle_publication_name" {
  description = "[custom] PostgreSQL publication name. Carried over from the app team's Postgres config; inert for an Oracle source"
  type        = string
  default     = ""
}

# ---- Oracle: worker capacity ------------------------------------------------
# Fixed PROVISIONED capacity (no autoscaling). Separate from the 5 Postgres
# connectors' worker vars so Oracle's ENI usage is tuned independently.

variable "oracle_worker_count" {
  description = "Fixed number of MSK Connect workers for the Oracle connector (provisioned capacity, no autoscaling). Each worker consumes one ENI in the connector subnets"
  type        = number
  default     = 1
}

variable "oracle_snapshot_mode" {
  description = "[debezium] Snapshot mode (initial, initial_only, schema_only, never)"
  type        = string
  default     = "initial"
}

# ---- Oracle: confluent-only -------------------------------------------------

variable "oracle_table_inclusion_regex" {
  description = <<-DESC
    [confluent] Regex matching the FULLY-QUALIFIED Oracle tables to capture.
    Confluent expects <SID-or-PDB>.<SCHEMA>.<TABLE> — note this includes the
    PDB/SID, unlike Debezium's schema.table form. Dots inside a literal name must
    be escaped as [.]. Example: EXETEST1[.]EXETER[.]SSS_AREAS
  DESC
  type        = string
  default     = ""
}

variable "oracle_start_from" {
  description = "[confluent] Where the connector begins reading: snapshot (full table snapshot first), current (SCN at startup), or force_current (current SCN, ignoring stored offsets)"
  type        = string
  default     = "snapshot"

  validation {
    condition     = contains(["snapshot", "current", "force_current"], var.oracle_start_from)
    error_message = "oracle_start_from must be one of: snapshot, current, force_current."
  }
}

variable "oracle_confluent_license" {
  description = "[confluent] Enterprise license key for the Oracle CDC connector. Empty = 30-day trial, after which the connector STOPS"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oracle_emit_tombstone_on_delete" {
  description = "[confluent] Emit a null-value tombstone record on delete (needed for log-compacted topics)"
  type        = bool
  default     = false
}

variable "oracle_tasks_max" {
  description = "Maximum number of Oracle connector tasks"
  type        = number
  default     = 1
}

# ---- S3 lifecycle -----------------------------------------------------------

variable "data_lake_ia_transition_days" {
  description = "Days before data-lake objects move to STANDARD_IA"
  type        = number
  default     = 30
}

variable "data_lake_glacier_transition_days" {
  description = "Days before data-lake objects move to GLACIER"
  type        = number
  default     = 90
}

variable "data_lake_noncurrent_expiry_days" {
  description = "Days before non-current data-lake versions expire"
  type        = number
  default     = 90
}

variable "logs_expiry_days" {
  description = "Days before MSK log objects expire"
  type        = number
  default     = 90
}

variable "logs_noncurrent_expiry_days" {
  description = "Days before non-current MSK log versions expire"
  type        = number
  default     = 30
}

# ---- KMS / Secrets ----------------------------------------------------------

variable "kms_deletion_window_days" {
  description = "KMS key deletion window in days (7-30)"
  type        = number
  default     = 30
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window in days"
  type        = number
  default     = 30
}

variable "password_length" {
  description = "Length of auto-generated Aurora master passwords"
  type        = number
  default     = 32
}

# ---- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Tags merged onto all resources"
  type        = map(string)
  default = {
    Owner      = "platform-team"
    CostCenter = "engineering"
    Terraform  = "true"
  }
}
