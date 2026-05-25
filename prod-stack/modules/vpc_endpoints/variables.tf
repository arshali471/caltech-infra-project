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
  description = "Subnets to place the SSM endpoint ENIs in"
  type        = list(string)
}

variable "public_route_table_ids" {
  description = "Route table IDs for public subnets — S3 Gateway endpoint adds a route here"
  type        = list(string)
}



variable "tags" {
  type    = map(string)
  default = {}
}
