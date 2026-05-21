variable "name" {
  type = string
}

variable "bootstrap_servers" {
  type = string
}

variable "msk_connect_sg_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "plugins_bucket_name" {
  type = string
}

variable "logs_bucket_name" {
  type = string
}

variable "msk_connect_role_arn" {
  type = string
}

variable "aurora_source_endpoint" {
  type = string
}

variable "aurora_source_db_name" {
  type = string
}

variable "aurora_source_username" {
  type      = string
  sensitive = true
}

variable "aurora_source_password" {
  type      = string
  sensitive = true
}


variable "custom_plugin_name" {
  description = "Name of the existing MSK Connect custom plugin created by the app team"
  type        = string
  default     = "caltech-poc-debezium-postgresql-connector-plugin"
}

variable "kafkaconnect_version" {
  type    = string
  default = "3.7.x"
}

variable "min_workers" {
  type    = number
  default = 1
}

variable "max_workers" {
  type    = number
  default = 2
}

variable "mcu_count" {
  type    = number
  default = 1
}

variable "scale_in_cpu_pct" {
  type    = number
  default = 20
}

variable "scale_out_cpu_pct" {
  type    = number
  default = 80
}

variable "key_converter" {
  type    = string
  default = "org.apache.kafka.connect.json.JsonConverter"
}

variable "value_converter" {
  type    = string
  default = "org.apache.kafka.connect.json.JsonConverter"
}

variable "converter_schemas_enabled" {
  type    = bool
  default = false
}

variable "offset_storage_replication_factor" {
  type    = number
  default = -1
}

variable "config_storage_replication_factor" {
  type    = number
  default = -1
}

variable "status_storage_replication_factor" {
  type    = number
  default = -1
}

variable "connector_class" {
  type    = string
  default = "io.debezium.connector.postgresql.PostgresConnector"
}

variable "tasks_max" {
  type    = number
  default = 1
}

variable "database_port" {
  type    = number
  default = 5432
}

variable "logical_decoding_plugin_name" {
  type    = string
  default = "pgoutput"
}

variable "replication_slot_name" {
  type    = string
  default = "dbz_students_slot"
}

variable "publication_name" {
  type    = string
  default = "dbz_publication"
}

variable "topic_prefix" {
  description = "Kafka topic prefix for Debezium events"
  type        = string
  default     = "students_poc_10"
}

variable "schema_include_list" {
  description = "PostgreSQL schemas to capture"
  type        = string
  default     = "public"
}

variable "table_include_list" {
  description = "Comma-separated tables to capture (schema.table)"
  type        = string
  default     = ""
}

variable "publication_autocreate_mode" {
  type    = string
  default = "all_tables"
}

variable "snapshot_mode" {
  type    = string
  default = "initial"
}

variable "decimal_handling_mode" {
  type    = string
  default = "double"
}

variable "time_precision_mode" {
  type    = string
  default = "connect"
}

variable "tombstones_on_delete" {
  type    = bool
  default = true
}

variable "heartbeat_interval_ms" {
  type    = number
  default = 30000
}

variable "log_delivery_prefix" {
  type    = string
  default = "msk-connect/"
}

variable "tags" {
  type    = map(string)
  default = {}
}
