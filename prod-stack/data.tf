###############################################################################
# data.tf — look up existing account identity and VPC only.
# AMI ID is provided directly via var.ec2_ami_id.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "existing" {
  id = var.vpc_id
}
