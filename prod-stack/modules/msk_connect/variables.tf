variable "name" {
  type = string
}

variable "connector_name_suffix" {
  description = "Appended to var.name to form connector/resource names (e.g. debezium-postgres-source-connector)"
  type        = string
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

variable "msk_connect_role_arn" {
  type = string
}

variable "custom_plugin_name" {
  description = "Name of the existing MSK Connect custom plugin"
  type        = string
}

variable "kafkaconnect_version" {
  type    = string
  default = "3.7.x"
}

variable "connector_configuration" {
  description = "Full connector configuration map — passed directly to the MSK Connect connector resource"
  type        = map(string)
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

variable "tags" {
  type    = map(string)
  default = {}
}
