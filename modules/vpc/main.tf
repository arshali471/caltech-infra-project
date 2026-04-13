###############################################################################
# modules/vpc/main.tf
# Creates: VPC, subnets (public / private-app / private-db), IGW, NAT GWs,
#          route tables, DB/cache subnet groups, VPC flow logs,
#          and all baseline security groups.
###############################################################################

locals {
  name = "${var.project}-${var.environment}"

  nat_count = var.enable_nat_gateway ? (
    var.single_nat_gateway ? 1 : length(var.availability_zones)
  ) : 0

  common_tags = merge(var.tags, {
    Module    = "vpc"
    ManagedBy = "terraform"
  })
}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc"
  })
}

###############################################################################
# Internet Gateway
###############################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-igw"
  })
}

###############################################################################
# Subnets — Public
###############################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                     = "${local.name}-public-${var.availability_zones[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

###############################################################################
# Subnets — Private App
###############################################################################

resource "aws_subnet" "private_app" {
  count = length(var.private_app_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name                              = "${local.name}-private-app-${var.availability_zones[count.index]}"
    Tier                              = "private-app"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

###############################################################################
# Subnets — Private DB
###############################################################################

resource "aws_subnet" "private_db" {
  count = length(var.private_db_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-db-${var.availability_zones[count.index]}"
    Tier = "private-db"
  })
}

###############################################################################
# Elastic IPs for NAT Gateways
###############################################################################

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# NAT Gateways
###############################################################################

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Route Table — Public
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Route Tables — Private App (one per AZ for HA)
###############################################################################

resource "aws_route_table" "private_app" {
  count  = length(var.private_app_subnet_cidrs)
  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[min(count.index, local.nat_count - 1)].id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-app-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private_app" {
  count = length(var.private_app_subnet_cidrs)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

###############################################################################
# Route Table — Private DB (no internet route — fully isolated)
###############################################################################

resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-db-rt"
  })
}

resource "aws_route_table_association" "private_db" {
  count = length(var.private_db_subnet_cidrs)

  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

###############################################################################
# DB Subnet Group (shared by RDS & Aurora)
###############################################################################

resource "aws_db_subnet_group" "this" {
  name        = "${local.name}-db-subnet-group"
  description = "DB subnet group for ${local.name}"
  subnet_ids  = aws_subnet.private_db[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name}-db-subnet-group"
  })
}

###############################################################################
# ElastiCache Subnet Group
###############################################################################

resource "aws_elasticache_subnet_group" "this" {
  name        = "${local.name}-cache-subnet-group"
  description = "ElastiCache subnet group for ${local.name}"
  subnet_ids  = aws_subnet.private_db[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name}-cache-subnet-group"
  })
}

###############################################################################
# VPC Flow Logs -> CloudWatch
###############################################################################

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/${local.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = local.common_tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${local.name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  name  = "${local.name}-vpc-flow-logs-policy"
  role  = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count           = var.enable_flow_logs ? 1 : 0
  vpc_id          = aws_vpc.this.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn

  tags = merge(local.common_tags, {
    Name = "${local.name}-flow-logs"
  })
}

###############################################################################
# Security Groups
###############################################################################

# ---- ALB Security Group (internet-facing) ---------------------------------

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "Allow HTTP/HTTPS inbound from internet to ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-alb-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- EKS Cluster Control-Plane Security Group ----------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name}-eks-cluster-sg"
  description = "EKS cluster API server security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Fargate pods to cluster API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_pods.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-eks-cluster-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- EKS Fargate Pods Security Group (Security Groups for Pods) ---------

resource "aws_security_group" "eks_pods" {
  name        = "${local.name}-eks-pods-sg"
  description = "EKS Fargate pod security group (Security Groups for Pods)"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Pod-to-pod (all protocols)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "ALB to Fargate pods (ephemeral NodePort range)"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-eks-pods-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- MSK Serverless Security Group (SASL/IAM only — port 9098) ----------

resource "aws_security_group" "msk" {
  name        = "${local.name}-msk-sg"
  description = "MSK Serverless — SASL/IAM (port 9098) from EKS Fargate pods"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "MSK Serverless SASL/IAM (9098) from private app subnets (Fargate pods)"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-msk-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- RDS / Aurora Serverless v2 Security Group (shared) ----------------

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Aurora Serverless v2 CDC source security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "PostgreSQL (5432) from private app subnets (Fargate pods)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-rds-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- Aurora PostgreSQL Serverless v2 Security Group --------------------

resource "aws_security_group" "aurora" {
  name        = "${local.name}-aurora-sg"
  description = "Aurora PostgreSQL Serverless v2 security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "PostgreSQL (5432) from private app subnets (Fargate pods)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-aurora-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- ElastiCache Serverless Redis Security Group -----------------------

resource "aws_security_group" "elasticache" {
  name        = "${local.name}-elasticache-sg"
  description = "ElastiCache Serverless Redis security group"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Redis (6379) from private app subnets (Fargate pods)"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.private_app_subnet_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name}-elasticache-sg" })
  lifecycle { create_before_destroy = true }
}

###############################################################################
# S3 VPC Gateway Endpoint
# Keeps S3 traffic (ECR images, CloudWatch Logs, ALB logs) inside the AWS
# network — eliminates NAT Gateway charges for S3 and lowers latency.
###############################################################################

data "aws_region" "current" {}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    aws_route_table.private_app[*].id,
    [aws_route_table.private_db.id],
    [aws_route_table.public.id],
  )

  tags = merge(local.common_tags, {
    Name = "${local.name}-s3-endpoint"
  })
}

###############################################################################
# ECR VPC Interface Endpoints
# Fargate pulls container images from ECR over the VPC private network —
# required when pods are in private subnets with no public IP.
###############################################################################

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.eks_pods.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.eks_pods.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-ecr-dkr-endpoint"
  })
}

###############################################################################
# CloudWatch Logs VPC Interface Endpoint
# Allows Fargate pods to ship logs to CloudWatch without going through NAT.
###############################################################################

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.eks_pods.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-logs-endpoint"
  })
}

###############################################################################
# Secrets Manager VPC Interface Endpoint
# Pods fetch DB credentials from Secrets Manager without NAT or public internet.
###############################################################################

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.eks_pods.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-secretsmanager-endpoint"
  })
}
