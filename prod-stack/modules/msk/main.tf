###############################################################################
# modules/msk — MSK Provisioned cluster
# App clients  → SASL/SCRAM (port 9096)
# MSK Connect  → IAM       (port 9098)
# Logs         → CloudWatch + Kinesis Firehose → S3
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

# ---- CloudWatch Log Group ---------------------------------------------------

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.name}/broker"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_cloudwatch_log_resource_policy" "msk" {
  policy_name = "${var.name}-msk-log-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.msk.arn}:*"
    }]
  })
}

# ---- Kinesis Firehose → S3 (bypasses bucket policy restriction) -------------

resource "aws_iam_role" "firehose" {
  name = "${var.name}-msk-firehose-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "${var.name}-msk-firehose-policy"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Write"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = [
          "arn:aws:s3:::${var.logs_bucket_name}",
          "arn:aws:s3:::${var.logs_bucket_name}/*"
        ]
      },
      {
        Sid      = "KMSEncrypt"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.s3_kms_key_arn]
      },
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = ["logs:PutLogEvents"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "msk" {
  name        = "${var.name}-msk-logs-to-s3"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = "arn:aws:s3:::${var.logs_bucket_name}"
    prefix             = "msk-broker-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "msk-broker-logs-errors/"
    buffering_size     = 64
    buffering_interval = 300
    compression_format = "GZIP"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_subscription_filter" "msk_to_firehose" {
  name            = "${var.name}-msk-to-firehose"
  log_group_name  = aws_cloudwatch_log_group.msk.name
  filter_pattern  = ""
  destination_arn = aws_kinesis_firehose_delivery_stream.msk.arn
  role_arn        = aws_iam_role.firehose.arn
  depends_on      = [aws_cloudwatch_log_group.msk]
}

# ---- MSK Broker Configuration -----------------------------------------------

resource "aws_msk_configuration" "this" {
  name           = "${var.name}-msk-config"
  kafka_versions = [var.kafka_version]

  server_properties = <<-PROPS
    auto.create.topics.enable=true
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=1
    log.retention.hours=168
  PROPS
}

# ---- MSK Cluster ------------------------------------------------------------

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

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
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
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
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
