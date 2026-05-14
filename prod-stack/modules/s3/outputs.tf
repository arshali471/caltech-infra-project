output "plugins_bucket_name"    { value = aws_s3_bucket.plugins.bucket }
output "plugins_bucket_arn"     { value = aws_s3_bucket.plugins.arn }
output "data_lake_bucket_name"  { value = aws_s3_bucket.data_lake.bucket }
output "data_lake_bucket_arn"   { value = aws_s3_bucket.data_lake.arn }
output "logs_bucket_name"       { value = aws_s3_bucket.logs.bucket }
output "logs_bucket_arn"        { value = aws_s3_bucket.logs.arn }
