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

# ---- Existing VPC -----------------------------------------------------------

variable "vpc_id" {
  description = "ID of the existing VPC to deploy into"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (EC2 — needs internet access)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (Aurora, ElastiCache, MSK Connect workers)"
  type        = list(string)
}

variable "msk_subnet_ids" {
  description = "Three private subnet IDs in 3 different AZs — one per MSK broker"
  type        = list(string)
}

variable "elasticache_subnet_ids" {
  description = "Two private subnet IDs with free IPs for ElastiCache Serverless VPC endpoints"
  type        = list(string)
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
  description = "EC2 instance type for the application server"
  type        = string
  default     = "t3.large"
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

# ---- Aurora Limitless variant ----------------------------------------------

variable "aurora_limitless_engine_version" {
  description = "Aurora PostgreSQL Limitless engine version (must end in -limitless)"
  type        = string
  default     = "16.13-limitless"
}

variable "aurora_limitless_min_acu" {
  description = "Minimum ACUs for the Limitless shard group"
  type        = number
  default     = 16
}

variable "aurora_limitless_max_acu" {
  description = "Maximum ACUs for the Limitless shard group"
  type        = number
  default     = 32
}

variable "aurora_limitless_compute_redundancy" {
  description = "Limitless shard standby count (0=single AZ, 1=one standby, 2=two standbys)"
  type        = number
  default     = 0
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

variable "msk_connect_sink_plugin_name" {
  description = "Name of the existing MSK Connect JDBC sink plugin created by the app team"
  type        = string
}

variable "sink_topics" {
  description = "Kafka topic(s) the sink connector consumes from"
  type        = string
  default     = "caltech_poc_10.public.student_enrollment"
}

variable "sink_table_name_format" {
  description = "Target table name in Aurora Sink DB"
  type        = string
  default     = "student_enrollment"
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
