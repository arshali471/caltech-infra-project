output "aurora_source_secret_arn" { value = aws_secretsmanager_secret.aurora_source.arn }
output "aurora_sink_secret_arn"   { value = aws_secretsmanager_secret.aurora_sink.arn }

output "aurora_source_password" {
  value     = random_password.aurora_source.result
  sensitive = true
}

output "aurora_sink_password" {
  value     = random_password.aurora_sink.result
  sensitive = true
}
