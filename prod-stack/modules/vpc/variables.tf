variable "name" {
  description = "Resource name prefix (e.g. caltech-poc)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string
}

variable "availability_zones" {
  description = "List of AZs to deploy into (e.g. [us-west-2a, us-west-2b, us-west-2c])"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway so private subnets can reach the internet (egress only)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
