###############################################################################
# modules/ec2/variables.tf
###############################################################################

variable "name" {
  description = "Name for the EC2 instance and all associated resources"
  type        = string
}

variable "role" {
  description = "Application role label used in tags (e.g. debezium, redis-sink, librechat)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to place the security group in"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "ami_id" {
  description = "Custom AMI ID. Leave empty to use the latest Amazon Linux 2023 x86_64."
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Assign a public IPv4 address. Set true only for public-subnet instances (e.g. Librechat)."
  type        = bool
  default     = false
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB (gp3, encrypted)"
  type        = number
  default     = 20
}

variable "ingress_rules" {
  description = "Inbound security group rules. Omit for outbound-only instances (e.g. workers using SSM)."
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = optional(list(string), [])
    self        = optional(bool, false)
  }))
  default = []
}

variable "additional_security_group_ids" {
  description = "Extra security group IDs to attach alongside the module-managed one"
  type        = list(string)
  default     = []
}

variable "additional_policy_arns" {
  description = "IAM managed policy ARNs to attach to the instance role (in addition to SSM)"
  type        = list(string)
  default     = []
}

variable "inline_policy" {
  description = "Inline IAM policy JSON document. Used to grant MSK SASL/IAM or Secrets Manager access."
  type        = string
  default     = ""
}

variable "user_data" {
  description = "EC2 user data as plain text. The module base64-encodes it before passing to AWS."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
