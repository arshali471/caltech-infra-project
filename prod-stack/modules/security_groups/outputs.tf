output "ec2_sg_id"          { value = aws_security_group.ec2.id }
output "msk_sg_id"          { value = aws_security_group.msk.id }
output "msk_connect_sg_id"  { value = aws_security_group.msk_connect.id }
output "aurora_source_sg_id"{ value = aws_security_group.aurora_source.id }
output "aurora_sink_sg_id"  { value = aws_security_group.aurora_sink.id }
output "elasticache_sg_id"  { value = aws_security_group.elasticache.id }
