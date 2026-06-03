###############################################################################
# data.tf — account identity + VPC lookups
#
# The two data sources are UNCONDITIONAL (always exist) — their `id` / `vpc_id`
# is picked from either var.vpc_id (existing VPC mode) or module.vpc[0]
# (new VPC mode). This avoids the "moved resource excluded by targeting"
# error that `count` on data sources would otherwise cause.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "existing" {
  id = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id
}

data "aws_route_tables" "public" {
  vpc_id = var.create_vpc ? module.vpc[0].vpc_id : var.vpc_id

  filter {
    name   = "association.subnet-id"
    values = local.public_subnet_ids
  }
}
