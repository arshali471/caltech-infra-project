variable "name" {
  type = string
}

variable "subnet_ids" {
  description = "One subnet per broker (3 brokers = 3 subnets in different AZs)"
  type        = list(string)
}

variable "security_group_id" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS key for MSK encryption at rest and SCRAM secret"
  type        = string
}

variable "kafka_version" {
  description = "Apache Kafka version — MSK valid values: 3.9.x, 3.9.x.kraft, 4.0.x.kraft, 4.1.x.kraft"
  type        = string
  default     = "3.9.x"
}

variable "broker_count" {
  description = "Number of broker nodes — must equal the number of subnet_ids (2 subnets = 2 or 4 brokers, 3 subnets = 3 or 6 brokers)"
  type        = number
  default     = 2
}

variable "broker_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m5.2xlarge"
}

variable "broker_volume_size_gb" {
  description = "EBS storage per broker in GB"
  type        = number
  default     = 250
}


variable "tags" {
  type    = map(string)
  default = {}
}
