###############################################################################
# modules/vpc_endpoints — Interface + Gateway endpoints for private subnet access
# SSM     — EC2 Session Manager (no public IP needed)
# STS     — IAM token generation for MSK Connect IAM auth in private subnets
# Secrets — SecretsManager access for MSK SCRAM credentials
# S3      — S3 access for MSK Connect plugin download (public + private subnets)
###############################################################################

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpce-sg"
  description = "VPC Interface Endpoints - allow HTTPS from EC2"
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

# ---- SSM Interface Endpoints (existing — keep resource name to avoid destroy) -

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

# ---- STS + SecretsManager (new — required for MSK Connect in private subnets) -

locals {
  msk_connect_services = {
    sts            = "com.amazonaws.${var.aws_region}.sts"
    secretsmanager = "com.amazonaws.${var.aws_region}.secretsmanager"
  }
}

resource "aws_vpc_endpoint" "msk_connect" {
  for_each = local.msk_connect_services

  vpc_id              = var.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-vpce-${each.key}" })
}

# ---- S3 Gateway — public subnets (existing — keep resource name) -------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.public_route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-vpce-s3" })
}

# ---- S3 Gateway — private subnets (new — for MSK Connect plugin download) ---

resource "aws_vpc_endpoint" "s3_private" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = merge(var.tags, { Name = "${var.name}-vpce-s3-private" })
}
