###############################################################################
# data.tf — account identity + (optional) VPC lookup for existing VPC mode.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# These data sources only run when create_vpc = false (using existing VPC).
# When create_vpc = true, module.vpc owns the VPC + route tables directly.

data "aws_vpc" "existing" {
  count = var.create_vpc ? 0 : 1
  id    = var.vpc_id
}

data "aws_route_tables" "public" {
  count  = var.create_vpc ? 0 : 1
  vpc_id = var.vpc_id

  filter {
    name   = "association.subnet-id"
    values = var.public_subnet_ids
  }
}
