variable "name" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.large"
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "root_volume_gb" {
  type    = number
  default = 50
}

variable "root_volume_type" {
  type    = string
  default = "gp3"
}

variable "ebs_kms_key_arn" {
  type = string
}

variable "imds_http_endpoint" {
  type    = string
  default = "enabled"
}

variable "imds_http_tokens" {
  type    = string
  default = "required"
}

variable "imds_http_put_response_hop_limit" {
  type    = number
  default = 1
}

variable "key_pair_name" {
  description = "Name of the existing EC2 key pair for SSH access"
  type        = string
}

variable "java_package" {
  type    = string
  default = "java-17-amazon-corretto"
}

variable "msk_iam_auth_version" {
  type    = string
  default = "1.1.9"
}

variable "tags" {
  type    = map(string)
  default = {}
}
