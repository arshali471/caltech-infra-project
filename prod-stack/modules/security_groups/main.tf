###############################################################################
# modules/security_groups — least-privilege SG per service
###############################################################################

# ---- EC2 (public subnet) ----------------------------------------------------

resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  description = "EC2 app server - SSH inbound, all outbound"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidr
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags      = merge(var.tags, { Name = "${var.name}-ec2-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- MSK Serverless ---------------------------------------------------------

resource "aws_security_group" "msk" {
  name        = "${var.name}-msk-sg"
  description = "MSK Provisioned - SASL/SCRAM port ${var.msk_scram_port} and IAM port ${var.msk_port}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MSK SASL/IAM from EC2 (MSK Connect uses this)"
    from_port       = var.msk_port
    to_port         = var.msk_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  ingress {
    description     = "MSK SASL/IAM from MSK Connect workers"
    from_port       = var.msk_port
    to_port         = var.msk_port
    protocol        = "tcp"
    security_groups = [aws_security_group.msk_connect.id]
  }

  ingress {
    description     = "MSK SASL/SCRAM from EC2 (app clients)"
    from_port       = var.msk_scram_port
    to_port         = var.msk_scram_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  ingress {
    description     = "MSK SASL/SCRAM from MSK Connect workers"
    from_port       = var.msk_scram_port
    to_port         = var.msk_scram_port
    protocol        = "tcp"
    security_groups = [aws_security_group.msk_connect.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags      = merge(var.tags, { Name = "${var.name}-msk-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- MSK Connect workers ----------------------------------------------------

resource "aws_security_group" "msk_connect" {
  name        = "${var.name}-msk-connect-sg"
  description = "MSK Connect workers - outbound to MSK and Aurora source"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags      = merge(var.tags, { Name = "${var.name}-msk-connect-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- Aurora Source ----------------------------------------------------------

resource "aws_security_group" "aurora_source" {
  name        = "${var.name}-aurora-source-sg"
  description = "Aurora source - PostgreSQL (${var.postgres_port}) from EC2 and MSK Connect"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = var.postgres_port
    to_port         = var.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  ingress {
    description     = "PostgreSQL from MSK Connect (Debezium)"
    from_port       = var.postgres_port
    to_port         = var.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.msk_connect.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags      = merge(var.tags, { Name = "${var.name}-aurora-source-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- Aurora Sink ------------------------------------------------------------

resource "aws_security_group" "aurora_sink" {
  name        = "${var.name}-aurora-sink-sg"
  description = "Aurora sink - PostgreSQL (${var.postgres_port}) from EC2 consumer"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = var.postgres_port
    to_port         = var.postgres_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags      = merge(var.tags, { Name = "${var.name}-aurora-sink-sg" })
  lifecycle { create_before_destroy = true }
}

# ---- ElastiCache Redis ------------------------------------------------------

resource "aws_security_group" "elasticache" {
  name        = "${var.name}-elasticache-sg"
  description = "ElastiCache Redis (${var.redis_port}) from EC2 Redis Sink consumer"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis TLS from EC2"
    from_port       = var.redis_port
    to_port         = var.redis_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags      = merge(var.tags, { Name = "${var.name}-elasticache-sg" })
  lifecycle { create_before_destroy = true }
}
