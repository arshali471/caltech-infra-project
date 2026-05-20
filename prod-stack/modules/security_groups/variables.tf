variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "msk_port" {
  description = "MSK IAM auth port (used by MSK Connect)"
  type        = number
  default     = 9098
}

variable "msk_scram_port" {
  description = "MSK SASL/SCRAM port (used by app clients)"
  type        = number
  default     = 9096
}

variable "postgres_port" {
  type    = number
  default = 5432
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "ssh_allowed_cidr" {
  description = "CIDRs allowed to SSH into the EC2 instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  type    = map(string)
  default = {}
}
