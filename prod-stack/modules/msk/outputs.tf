output "cluster_arn"           { value = aws_msk_cluster.this.arn }
output "bootstrap_brokers"     { value = aws_msk_cluster.this.bootstrap_brokers_sasl_scram }
output "bootstrap_brokers_iam" { value = aws_msk_cluster.this.bootstrap_brokers_sasl_iam }
output "scram_secret_arn"      { value = aws_secretsmanager_secret.scram.arn }
output "scram_username"        { value = "kafkauser" }
