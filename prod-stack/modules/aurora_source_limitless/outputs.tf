output "endpoint"        { value = aws_rds_cluster.this.endpoint }
output "reader_endpoint" { value = aws_rds_cluster.this.reader_endpoint }
output "cluster_arn"     { value = aws_rds_cluster.this.arn }
output "cluster_id"      { value = aws_rds_cluster.this.cluster_identifier }
output "shard_group_id"  { value = aws_rds_shard_group.this.db_shard_group_identifier }
