###############################################################################
# modules/rds/main.tf
# Creates: Aurora PostgreSQL Serverless v2 cluster (Debezium CDC source)
#          with KMS encryption, logical replication, auto-scaling ACUs,
#          Secrets Manager for credentials, and enhanced monitoring.
#
# Aurora Serverless v2 key points for CDC:
#   - engine_mode = "provisioned"  (Serverless v2 uses provisioned mode)
#   - instance_class = "db.serverless"  (scales between min/max ACUs)
#   - rds.logical_replication = 1 in cluster parameter group (Debezium WAL)
#   - No option groups (Aurora PostgreSQL does not support option groups)
###############################################################################

locals {
  common_tags = merge(var.tags, {
    Module    = "rds"
    ManagedBy = "terraform"
  })

  # Derive Aurora parameter group family from engine_version
  # e.g. "15.4" → "aurora-postgresql15"
  pg_major_version  = split(".", var.engine_version)[0]
  cluster_pg_family = var.parameter_group_family != "" ? var.parameter_group_family : "aurora-postgresql${local.pg_major_version}"
  instance_pg_family = (
    var.instance_parameter_group_family != ""
    ? var.instance_parameter_group_family
    : "aurora-postgresql${local.pg_major_version}"
  )
}

###############################################################################
# KMS Key — Aurora encryption at rest
###############################################################################

resource "aws_kms_key" "rds" {
  description             = "KMS key for Aurora Serverless v2 CDC cluster ${var.identifier}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.identifier}-rds-kms"
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.identifier}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

###############################################################################
# Secrets Manager — Aurora master password
###############################################################################

resource "random_password" "rds_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rds_master" {
  name                    = "${var.identifier}/master-credentials"
  description             = "Aurora Serverless v2 CDC source credentials for ${var.identifier}"
  kms_key_id              = aws_kms_key.rds.arn
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.identifier}-master-secret"
  })
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.rds_master.result
    engine   = "aurora-postgresql"
    host     = aws_rds_cluster.this.endpoint
    port     = aws_rds_cluster.this.port
    dbname   = var.database_name
  })
}

###############################################################################
# IAM Role — Enhanced Monitoring
###############################################################################

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.identifier}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  role       = aws_iam_role.rds_monitoring.name
}

###############################################################################
# Cluster Parameter Group — logical replication for Debezium CDC
###############################################################################

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.identifier}-cluster-pg"
  family      = local.cluster_pg_family
  description = "Aurora Serverless v2 cluster params for ${var.identifier} (Debezium CDC source)"

  # Required for Debezium logical replication
  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "wal_sender_timeout"
    value = "0"
  }

  parameter {
    name  = "max_wal_senders"
    value = tostring(var.max_wal_senders)
  }

  parameter {
    name  = "max_replication_slots"
    value = tostring(var.max_replication_slots)
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement)
  }

  parameter {
    name  = "log_statement"
    value = var.log_statement
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.common_tags
}

###############################################################################
# Instance Parameter Group
###############################################################################

resource "aws_db_parameter_group" "this" {
  name        = "${var.identifier}-instance-pg"
  family      = local.instance_pg_family
  description = "Aurora Serverless v2 instance params for ${var.identifier}"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = local.common_tags
}

###############################################################################
# Aurora Serverless v2 Cluster (CDC Source)
###############################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.identifier
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  engine_mode        = "provisioned" # Required for Aurora Serverless v2

  database_name   = var.database_name
  master_username = var.master_username
  master_password = random_password.rds_master.result

  # Aurora Serverless v2 — scales between min and max ACUs automatically
  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity_units
    max_capacity = var.max_capacity_units
  }

  db_subnet_group_name            = var.subnet_group_name
  vpc_security_group_ids          = var.security_group_ids
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"
  copy_tags_to_snapshot     = true

  deletion_protection                 = var.deletion_protection
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = var.cloudwatch_log_exports

  allow_major_version_upgrade = false

  tags = merge(local.common_tags, {
    Name = var.identifier
  })

  lifecycle {
    ignore_changes = [master_password]
  }
}

###############################################################################
# Aurora Serverless v2 Cluster Instances
###############################################################################

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.identifier}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless" # Aurora Serverless v2 instance class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name = aws_db_parameter_group.this.name

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention

  auto_minor_version_upgrade   = true
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  tags = merge(local.common_tags, {
    Name = "${var.identifier}-instance-${count.index + 1}"
  })
}
