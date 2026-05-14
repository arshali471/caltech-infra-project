output "endpoint_address" { value = aws_elasticache_serverless_cache.this.endpoint[0].address }
output "endpoint_port"    { value = aws_elasticache_serverless_cache.this.endpoint[0].port }
output "cache_name"       { value = aws_elasticache_serverless_cache.this.name }
