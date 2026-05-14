###############################################################################
# modules/secrets — Aurora master passwords in Secrets Manager (KMS-encrypted)
###############################################################################

resource "random_password" "aurora_source" {
  length           = var.password_length
  special          = true
  override_special = var.password_special_chars
}

resource "random_password" "aurora_sink" {
  length           = var.password_length
  special          = true
  override_special = var.password_special_chars
}

resource "aws_secretsmanager_secret" "aurora_source" {
  name                    = "${var.name}/aurora-source/master-password"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = merge(var.tags, { Name = "${var.name}-aurora-source-secret" })
}

resource "aws_secretsmanager_secret_version" "aurora_source" {
  secret_id = aws_secretsmanager_secret.aurora_source.id
  secret_string = jsonencode({
    username = var.aurora_source_master_username
    password = random_password.aurora_source.result
  })
}

resource "aws_secretsmanager_secret" "aurora_sink" {
  name                    = "${var.name}/aurora-sink/master-password"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = merge(var.tags, { Name = "${var.name}-aurora-sink-secret" })
}

resource "aws_secretsmanager_secret_version" "aurora_sink" {
  secret_id = aws_secretsmanager_secret.aurora_sink.id
  secret_string = jsonencode({
    username = var.aurora_sink_master_username
    password = random_password.aurora_sink.result
  })
}
