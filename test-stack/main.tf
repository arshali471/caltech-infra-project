###############################################################################
# test-stack/main.tf
#
# Minimal test environment for validating MSK (Kafka) and ElastiCache (Redis)
# in isolation — no EKS, ALB, Aurora, or RDS required.
#
# Topology:
#   Public subnets  → NAT Gateway + EC2 bastion (SSM access, no open SSH port)
#   Private subnets → MSK Serverless + ElastiCache Serverless Redis
#
# Access pattern for testing:
#   aws ssm start-session --target <bastion-instance-id>
#   Then use kafka-topics.sh / redis-cli from inside the bastion.
###############################################################################

locals {
  name = "${var.project}-test"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

###############################################################################
# VPC
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}

###############################################################################
# Subnets
###############################################################################

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-public-${var.availability_zones[count.index]}" }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name}-private-${var.availability_zones[count.index]}" }
}

###############################################################################
# NAT Gateway (single — test environment)
###############################################################################

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]
  tags       = { Name = "${local.name}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.this]
  tags          = { Name = "${local.name}-nat" }
}

###############################################################################
# Route Tables
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = { Name = "${local.name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# Security Groups
###############################################################################

# MSK Serverless — SASL/IAM on port 9098, reachable from anywhere in the VPC
resource "aws_security_group" "msk" {
  name        = "${local.name}-msk-sg"
  description = "MSK Serverless SASL/IAM (9098) from test VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "MSK SASL/IAM from VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-msk-sg" }
  lifecycle { create_before_destroy = true }
}

# ElastiCache Serverless — Redis TLS on port 6379, reachable from VPC
resource "aws_security_group" "elasticache" {
  name        = "${local.name}-redis-sg"
  description = "ElastiCache Serverless Redis TLS (6379) from test VPC"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Redis TLS from VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-redis-sg" }
  lifecycle { create_before_destroy = true }
}

# Bastion — outbound only; access via SSM (no inbound SSH port)
resource "aws_security_group" "bastion" {
  name        = "${local.name}-bastion-sg"
  description = "Bastion outbound only - inbound access via SSM Session Manager"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-bastion-sg" }
  lifecycle { create_before_destroy = true }
}

###############################################################################
# MSK Serverless (Kafka)
###############################################################################

module "msk" {
  source = "../modules/msk"

  cluster_name       = "${local.name}-kafka"
  environment        = "test"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.msk.id]
  tags               = var.tags
}

###############################################################################
# ElastiCache Serverless Redis
###############################################################################

module "elasticache" {
  source = "../modules/elasticache"

  cluster_id           = "${local.name}-redis"
  environment          = "test"
  major_engine_version = "7"
  min_data_storage_gb  = var.redis_min_data_storage_gb
  max_data_storage_gb  = var.redis_max_data_storage_gb
  min_ecpu_per_second  = var.redis_min_ecpu_per_second
  max_ecpu_per_second  = var.redis_max_ecpu_per_second

  snapshot_retention_limit = 0

  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.elasticache.id]
  tags               = var.tags
}

###############################################################################
# Bastion EC2 — SSM Session Manager (no SSH key, no open port)
#
# Connect:  aws ssm start-session --target <bastion_instance_id> --region us-west-1
#
# Test MSK (after connecting):
#   source /etc/profile.d/kafka.sh
#   kafka-topics.sh --bootstrap-server <MSK_ENDPOINT> \
#     --command-config /opt/kafka/config/client.properties \
#     --create --topic test-topic --partitions 1 --replication-factor 1
#   echo "hello kafka" | kafka-console-producer.sh \
#     --bootstrap-server <MSK_ENDPOINT> \
#     --producer.config /opt/kafka/config/client.properties \
#     --topic test-topic
#
# Test Redis (after connecting):
#   redis-cli -h <REDIS_PRIMARY_ENDPOINT> -p 6379 --tls ping
###############################################################################

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "bastion" {
  name = "${local.name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "msk_access" {
  name = "${local.name}-msk-access"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterConnect"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster",
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${local.name}-kafka/*"
      },
      {
        Sid    = "MSKTopics"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DeleteTopic",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:AlterTopicDynamicConfiguration",
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${local.name}-kafka/*/*"
      },
      {
        Sid    = "MSKGroups"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:DeleteGroup",
        ]
        Resource = "arn:aws:kafka:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:group/${local.name}-kafka/*/*"
      },
      {
        Sid    = "MSKControlPlane"
        Effect = "Allow"
        Action = [
          "kafka:DescribeClusterV2",
          "kafka:ListClustersV2",
          "kafka:GetBootstrapBrokers",
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name}-bastion-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    yum update -y

    yum install -y java-17-amazon-corretto-headless

    cd /opt
    curl -sO https://archive.apache.org/dist/kafka/3.7.0/kafka_2.13-3.7.0.tgz
    tar -xzf kafka_2.13-3.7.0.tgz
    ln -s /opt/kafka_2.13-3.7.0 /opt/kafka
    echo 'export PATH=$PATH:/opt/kafka/bin' > /etc/profile.d/kafka.sh

    curl -sL \
      https://github.com/aws/aws-msk-iam-auth/releases/download/v2.2.0/aws-msk-iam-auth-2.2.0-all.jar \
      -o /opt/kafka/libs/aws-msk-iam-auth-2.2.0-all.jar

    cat > /opt/kafka/config/client.properties <<'PROPS'
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
PROPS

    yum install -y redis6

    echo "Bastion setup complete" > /var/log/bastion-setup.log
  EOF
  )

  tags = { Name = "${local.name}-bastion" }

  depends_on = [aws_nat_gateway.this]
}
