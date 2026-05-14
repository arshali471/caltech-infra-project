###############################################################################
# modules/kms — one CMK per service, all with annual key rotation
###############################################################################

resource "aws_kms_key" "ebs" {
  description             = "EBS volume encryption - ${var.name}"
  deletion_window_in_days = var.deletion_window_days
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-ebs-kms" })
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.name}-ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_kms_key" "s3" {
  description             = "S3 bucket encryption - ${var.name}"
  deletion_window_in_days = var.deletion_window_days
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-s3-kms" })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "aurora" {
  description             = "Aurora cluster encryption - ${var.name}"
  deletion_window_in_days = var.deletion_window_days
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-aurora-kms" })
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.name}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

resource "aws_kms_key" "redis" {
  description             = "ElastiCache Redis encryption - ${var.name}"
  deletion_window_in_days = var.deletion_window_days
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-redis-kms" })
}

resource "aws_kms_alias" "redis" {
  name          = "alias/${var.name}-redis"
  target_key_id = aws_kms_key.redis.key_id
}

resource "aws_kms_key" "secrets" {
  description             = "Secrets Manager encryption - ${var.name}"
  deletion_window_in_days = var.deletion_window_days
  enable_key_rotation     = true
  tags                    = merge(var.tags, { Name = "${var.name}-secrets-kms" })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
