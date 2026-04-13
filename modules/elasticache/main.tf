###############################################################################
# modules/elasticache/main.tf
# Creates: ElastiCache Serverless Redis cache with KMS encryption,
#          capacity limits, automated snapshots, and CloudWatch alarms.
#
# ElastiCache Serverless key points:
#   - No node type, no cluster count, no parameter group required
#   - Capacity defined as max data storage (GB) and ECPU/s
#   - Always-on TLS; access controlled via VPC security groups
#   - Supports KMS for at-rest encryption (kms_key_id)
#   - Uses subnet_ids directly (not a subnet group)
###############################################################################

locals {
  common_tags = merge(var.tags, {
    Module    = "elasticache"
    ManagedBy = "terraform"
  })
}

###############################################################################
# KMS Key — ElastiCache at-rest encryption
###############################################################################

resource "aws_kms_key" "redis" {
  description             = "KMS key for ElastiCache Serverless cache ${var.cluster_id}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_id}-redis-kms"
  })
}

resource "aws_kms_alias" "redis" {
  name          = "alias/${var.cluster_id}-redis"
  target_key_id = aws_kms_key.redis.key_id
}

###############################################################################
# ElastiCache Serverless Cache
###############################################################################

resource "aws_elasticache_serverless_cache" "this" {
  engine = "redis"
  name   = var.cluster_id

  description          = "Serverless Redis cache for ${var.cluster_id} (${var.environment})"
  major_engine_version = var.major_engine_version

  # Capacity limits — serverless scales automatically within these bounds
  cache_usage_limits {
    data_storage {
      maximum = var.max_data_storage_gb
      minimum = var.min_data_storage_gb
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = var.max_ecpu_per_second
      minimum = var.min_ecpu_per_second
    }
  }

  kms_key_id         = aws_kms_key.redis.arn
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  # Snapshots
  snapshot_retention_limit = var.snapshot_retention_limit
  daily_snapshot_time      = var.daily_snapshot_time

  tags = merge(local.common_tags, {
    Name = var.cluster_id
  })
}

###############################################################################
# CloudWatch Alarms — Serverless Redis health
###############################################################################

resource "aws_cloudwatch_metric_alarm" "redis_ecpu" {
  alarm_name          = "${var.cluster_id}-high-ecpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ElastiCacheProcessingUnits"
  namespace           = "AWS/ElastiCache"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_ecpu_threshold
  alarm_description   = "ElastiCache Serverless ECPU exceeded ${var.alarm_ecpu_threshold} per period"

  dimensions = {
    CacheClusterId = var.cluster_id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.cluster_id}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "BytesUsedForCache"
  namespace           = "AWS/ElastiCache"
  period              = var.alarm_period
  statistic           = "Average"
  # Threshold in bytes (convert GB to bytes)
  threshold         = var.alarm_memory_threshold_gb * 1024 * 1024 * 1024
  alarm_description = "ElastiCache Serverless data storage exceeded ${var.alarm_memory_threshold_gb} GB"

  dimensions = {
    CacheClusterId = var.cluster_id
  }

  tags = local.common_tags
}

