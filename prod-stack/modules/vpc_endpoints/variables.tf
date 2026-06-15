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

variable "s3_gateway_route_table_ids" {
  description = "Route table IDs to associate with the S3 Gateway endpoint. Pass private route tables when EC2 lives in private subnets so S3 is reachable privately."
  type        = list(string)
}



variable "tags" {
  type    = map(string)
  default = {}
}
