variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "subnet_ids" {
  description = "Subnets to place the endpoint ENIs in (same subnet as EC2)"
  type        = list(string)
}


variable "tags" {
  type    = map(string)
  default = {}
}
