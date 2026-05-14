###############################################################################
# modules/ec2/main.tf
# Creates: EC2 instance with IMDSv2, encrypted EBS, SSM access, and an
#          instance-specific security group + IAM role.
#
# Used for every application workload in the EC2-based architecture:
#   transaction-simulator, debezium, redis-sink, postgres-sink, librechat
###############################################################################

locals {
  common_tags = merge(var.tags, {
    Module    = "ec2"
    ManagedBy = "terraform"
    Role      = var.role
  })
}

###############################################################################
# AMI — Amazon Linux 2023 (latest x86_64)
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

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "Security group for ${var.role}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = lookup(ingress.value, "cidr_blocks", [])
      self        = lookup(ingress.value, "self", false)
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${var.name}-sg" })
  lifecycle { create_before_destroy = true }
}

###############################################################################
# IAM Role — SSM access + optional additional policies
###############################################################################

resource "aws_iam_role" "this" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.inline_policy != "" ? 1 : 0

  name   = "${var.name}-policy"
  role   = aws_iam_role.this.id
  policy = var.inline_policy
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-profile"
  role = aws_iam_role.this.name

  tags = local.common_tags
}

###############################################################################
# EC2 Instance
###############################################################################

resource "aws_instance" "this" {
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = concat([aws_security_group.this.id], var.additional_security_group_ids)
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = var.associate_public_ip

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  # IMDSv2 required — blocks SSRF-based credential theft via metadata endpoint
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = var.user_data != "" ? base64encode(var.user_data) : null

  tags = merge(local.common_tags, { Name = var.name })
}
