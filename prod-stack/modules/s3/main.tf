###############################################################################
# modules/s3 — 3 buckets: msk-plugins, data-lake, msk-logs
# Bug fix: bucket policy ARNs now use exact bucket names via a map,
#          avoiding the previous msk-data-lake/data-lake name mismatch.
###############################################################################

locals {
  bucket_names = {
    plugins   = "${var.name}-msk-plugins"
    data_lake = "${var.name}-data-lake"
    logs      = "${var.name}-msk-logs"
  }
}

# Shared TLS + account-only bucket policy, keyed by bucket name
data "aws_iam_policy_document" "secure" {
  for_each = local.bucket_names

  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${each.value}", "arn:aws:s3:::${each.value}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyOtherAccounts"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = ["arn:aws:s3:::${each.value}", "arn:aws:s3:::${each.value}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalAccount"
      values   = [var.account_id]
    }
  }
}

###############################################################################
# Bucket 1 — MSK Connect plugin storage (Debezium connector ZIP)
###############################################################################

resource "aws_s3_bucket" "plugins" {
  bucket        = local.bucket_names.plugins
  force_destroy = false
  tags          = merge(var.tags, { Name = local.bucket_names.plugins, Purpose = "MSK Connect Debezium plugin" })
}

resource "aws_s3_bucket_versioning" "plugins" {
  bucket = aws_s3_bucket.plugins.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "plugins" {
  bucket = aws_s3_bucket.plugins.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "plugins" {
  bucket                  = aws_s3_bucket.plugins.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "plugins" {
  bucket = aws_s3_bucket.plugins.id
  policy = data.aws_iam_policy_document.secure["plugins"].json
}

###############################################################################
# Bucket 2 — Data lake (archived Kafka consumer output)
###############################################################################

resource "aws_s3_bucket" "data_lake" {
  bucket        = local.bucket_names.data_lake
  force_destroy = false
  tags          = merge(var.tags, { Name = local.bucket_names.data_lake, Purpose = "Kafka consumer event archive" })
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  policy = data.aws_iam_policy_document.secure["data_lake"].json
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    id     = "tiered-storage"
    status = "Enabled"
    filter { prefix = "" }
    transition {
      days          = var.data_lake_ia_transition_days
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = var.data_lake_glacier_transition_days
      storage_class = "GLACIER"
    }
    noncurrent_version_expiration { noncurrent_days = var.data_lake_noncurrent_expiry_days }
  }
}

###############################################################################
# Bucket 3 — MSK Connect worker logs
###############################################################################

resource "aws_s3_bucket" "logs" {
  bucket        = local.bucket_names.logs
  force_destroy = false
  tags          = merge(var.tags, { Name = local.bucket_names.logs, Purpose = "MSK Connect worker logs" })
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.secure["logs"].json
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = var.logs_expiry_days }
    noncurrent_version_expiration { noncurrent_days = var.logs_noncurrent_expiry_days }
  }
}
