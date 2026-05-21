###############################################################################
# modules/msk — MSK Provisioned cluster
# App clients  → SASL/SCRAM (port 9096)
# MSK Connect  → IAM       (port 9098)
###############################################################################

resource "random_password" "scram" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "scram" {
  name       = "AmazonMSK_${var.name}-scram"
  kms_key_id = var.kms_key_arn
  tags       = merge(var.tags, { Name = "AmazonMSK_${var.name}-scram" })
}

resource "aws_secretsmanager_secret_version" "scram" {
  secret_id     = aws_secretsmanager_secret.scram.id
  secret_string = jsonencode({
    username = "kafkauser"
    password = random_password.scram.result
  })
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.name}/broker"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_msk_cluster" "this" {
  cluster_name           = "${var.name}-msk"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.subnet_ids
    security_groups = [var.security_group_id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size_gb
      }
    }
  }

  client_authentication {
    sasl {
      scram = true
      iam   = true
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.kms_key_arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  enhanced_monitoring = "PER_BROKER"

  logging_info {
    broker_logs {
      s3 {
        enabled = true
        bucket  = var.logs_bucket_name
        prefix  = "msk-broker-logs/"
      }
      cloudwatch_logs {
        enabled   = true
        log_group = "/aws/msk/${var.name}/broker"
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-msk", Purpose = "CDC event streaming" })
}

resource "aws_msk_scram_secret_association" "this" {
  cluster_arn     = aws_msk_cluster.this.arn
  secret_arn_list = [aws_secretsmanager_secret.scram.arn]
  depends_on      = [aws_secretsmanager_secret_version.scram]
}
