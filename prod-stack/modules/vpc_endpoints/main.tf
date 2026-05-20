###############################################################################
# modules/vpc_endpoints — SSM interface endpoints
# Allows EC2 instances without public IPs to use SSM Session Manager
# by routing SSM traffic through the private AWS network.
#
# NOTE: private_dns_enabled=true overrides SSM DNS for the entire VPC, so the
# endpoint SG must allow port 443 from all instances in the VPC (not just one SG).
###############################################################################

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpce-sg"
  description = "VPC Interface Endpoints - allow HTTPS from all VPC instances"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from all instances in VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-vpce-sg" })
}

locals {
  ssm_services = {
    ssm         = "com.amazonaws.${var.aws_region}.ssm"
    ssmmessages = "com.amazonaws.${var.aws_region}.ssmmessages"
    ec2messages = "com.amazonaws.${var.aws_region}.ec2messages"
  }
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = local.ssm_services

  vpc_id              = var.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-vpce-${each.key}" })
}
