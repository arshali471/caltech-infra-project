###############################################################################
# modules/iam — EC2 app role + MSK Connect service execution role
###############################################################################

locals {
  msk_topic_arn = "arn:aws:kafka:${var.aws_region}:${var.account_id}:topic/${var.name}/*"
  msk_group_arn = "arn:aws:kafka:${var.aws_region}:${var.account_id}:group/${var.name}/*"
}

###############################################################################
# Role 1 — EC2 application server (SSM + MSK + Secrets + S3)
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_app" {
  name               = "${var.name}-ec2-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = merge(var.tags, { Name = "${var.name}-ec2-app-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_app" {
  statement {
    sid     = "MSKConnect"
    effect  = "Allow"
    actions = ["kafka-cluster:Connect", "kafka-cluster:AlterCluster", "kafka-cluster:DescribeCluster"]
    resources = [var.msk_cluster_arn]
  }

  statement {
    sid     = "MSKTopics"
    effect  = "Allow"
    actions = ["kafka-cluster:*Topic*", "kafka-cluster:WriteData", "kafka-cluster:ReadData"]
    resources = [local.msk_topic_arn]
  }

  statement {
    sid     = "MSKGroups"
    effect  = "Allow"
    actions = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = [local.msk_group_arn]
  }

  statement {
    sid     = "SecretsRead"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.aurora_source_secret_arn, var.aurora_sink_secret_arn]
  }

  statement {
    sid     = "SecretsKMS"
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.secrets_kms_key_arn]
  }

  statement {
    sid     = "S3PluginRead"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.s3_plugins_bucket_arn, "${var.s3_plugins_bucket_arn}/*"]
  }

  statement {
    sid     = "S3DataLakeWrite"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [var.s3_data_lake_bucket_arn, "${var.s3_data_lake_bucket_arn}/*"]
  }

  statement {
    sid     = "S3KMS"
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.s3_kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ec2_app" {
  name   = "${var.name}-ec2-app-policy"
  role   = aws_iam_role.ec2_app.id
  policy = data.aws_iam_policy_document.ec2_app.json
}

resource "aws_iam_instance_profile" "ec2_app" {
  name = "${var.name}-ec2-app-profile"
  role = aws_iam_role.ec2_app.name
}

###############################################################################
# Role 2 — MSK Connect service execution role (kafkaconnect.amazonaws.com)
###############################################################################

data "aws_iam_policy_document" "msk_connect_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["kafkaconnect.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "msk_connect" {
  name               = "${var.name}-msk-connect-role"
  assume_role_policy = data.aws_iam_policy_document.msk_connect_assume.json
  tags               = merge(var.tags, { Name = "${var.name}-msk-connect-role" })
}

data "aws_iam_policy_document" "msk_connect" {
  statement {
    sid     = "MSKConnect"
    effect  = "Allow"
    actions = ["kafka-cluster:Connect", "kafka-cluster:AlterCluster", "kafka-cluster:DescribeCluster"]
    resources = [var.msk_cluster_arn]
  }

  statement {
    sid     = "MSKTopics"
    effect  = "Allow"
    actions = ["kafka-cluster:*Topic*", "kafka-cluster:WriteData", "kafka-cluster:ReadData"]
    resources = [local.msk_topic_arn]
  }

  statement {
    sid     = "MSKGroups"
    effect  = "Allow"
    actions = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
    resources = [local.msk_group_arn]
  }

  statement {
    sid     = "S3Plugin"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.s3_plugins_bucket_arn, "${var.s3_plugins_bucket_arn}/*"]
  }

  statement {
    sid     = "S3Logs"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
    resources = [var.s3_logs_bucket_arn, "${var.s3_logs_bucket_arn}/*"]
  }

  statement {
    sid     = "S3KMS"
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.s3_kms_key_arn]
  }

  statement {
    sid     = "SecretsRead"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [var.aurora_source_secret_arn]
  }

  statement {
    sid     = "SecretsKMS"
    effect  = "Allow"
    actions = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.secrets_kms_key_arn]
  }

  statement {
    sid     = "VPCNetworking"
    effect  = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DeleteNetworkInterface",
      "ec2:AssignPrivateIpAddresses",
      "ec2:UnassignPrivateIpAddresses",
    ]
    resources = ["*"]
  }

  statement {
    sid     = "CloudWatchLogs"
    effect  = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogDelivery",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "msk_connect" {
  name   = "${var.name}-msk-connect-policy"
  role   = aws_iam_role.msk_connect.id
  policy = data.aws_iam_policy_document.msk_connect.json
}
