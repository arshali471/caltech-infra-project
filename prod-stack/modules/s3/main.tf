###############################################################################
# modules/s3 — 3 buckets: msk-plugins, data-lake, msk-logs
# Note: public-access-block and bucket policies are omitted — enforced by org SCP.
###############################################################################

locals {
  bucket_names = {
    plugins   = "${var.name}-msk-plugins"
    data_lake = "${var.name}-data-lake"
    logs      = "${var.name}-msk-logs"
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
