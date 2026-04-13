###############################################################################
# modules/elasticache/outputs.tf
###############################################################################

output "serverless_cache_id" {
  description = "ElastiCache Serverless cache ID"
  value       = aws_elasticache_serverless_cache.this.id
}

output "serverless_cache_arn" {
  description = "ElastiCache Serverless cache ARN"
  value       = aws_elasticache_serverless_cache.this.arn
}

output "primary_endpoint_address" {
  description = "Redis Serverless primary endpoint address (for writes)"
  value       = aws_elasticache_serverless_cache.this.endpoint[0].address
  sensitive   = true
}

output "reader_endpoint_address" {
  description = "Redis Serverless reader endpoint address (for reads)"
  value       = aws_elasticache_serverless_cache.this.reader_endpoint[0].address
  sensitive   = true
}

output "endpoint_port" {
  description = "Redis Serverless endpoint port"
  value       = aws_elasticache_serverless_cache.this.endpoint[0].port
}

output "kms_key_arn" {
  description = "ARN of the KMS key for Redis at-rest encryption"
  value       = aws_kms_key.redis.arn
}

