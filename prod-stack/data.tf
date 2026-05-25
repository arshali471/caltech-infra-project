###############################################################################
# data.tf — look up existing account identity and VPC only.
# AMI ID is provided directly via var.ec2_ami_id.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_route_tables" "public" {
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = var.public_subnet_ids
  }
}

data "aws_route_tables" "private" {
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = var.private_subnet_ids
  }
}
