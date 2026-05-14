###############################################################################
# modules/elasticache — ElastiCache Serverless, TLS enforced, KMS encrypted
# engine: "redis" or "valkey"
###############################################################################

resource "aws_elasticache_serverless_cache" "this" {
  engine = var.engine
  name   = "${var.name}-redis"

  cache_usage_limits {
    data_storage {
      minimum = var.min_data_storage_gb
      maximum = var.max_data_storage_gb
      unit    = "GB"
    }
    ecpu_per_second {
      minimum = var.min_ecpu_per_second
      maximum = var.max_ecpu_per_second
    }
  }

  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]
  kms_key_id         = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-redis", Purpose = "Redis Sink consumer target" })
}
