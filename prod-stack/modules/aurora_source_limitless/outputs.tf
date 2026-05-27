output "endpoint"        { value = data.aws_rds_cluster.this.endpoint }
output "reader_endpoint" { value = data.aws_rds_cluster.this.reader_endpoint }
output "cluster_arn"     { value = data.aws_rds_cluster.this.arn }
output "cluster_id"      { value = local.cluster_id }
output "shard_group_id"  { value = local.shard_id }
