variable "name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "msk_cluster_arn" {
  type    = string
  default = "*"
}

variable "s3_plugins_bucket_arn" {
  type = string
}

variable "s3_data_lake_bucket_arn" {
  type = string
}

variable "s3_logs_bucket_arn" {
  type = string
}

variable "s3_kms_key_arn" {
  type = string
}

variable "secrets_kms_key_arn" {
  type = string
}

variable "aurora_source_secret_arn" {
  type = string
}

variable "aurora_sink_secret_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
