###############################################################################
# modules/aurora/main.tf
# Creates: Aurora PostgreSQL cluster with KMS encryption, IAM auth,
#          enhanced monitoring, auto-scaling readers, and Secrets Manager
#          for master password rotation.
###############################################################################

locals {
  common_tags = merge(var.tags, {
    Module    = "aurora"
    ManagedBy = "terraform"
  })

  # Derive parameter group family from engine_version (e.g. "15.4" → "aurora-postgresql15")
  # Override by setting var.cluster_parameter_group_family / var.instance_parameter_group_family
  pg_major_version = split(".", var.engine_version)[0]
  cluster_pg_family = (
    var.cluster_parameter_group_family != ""
    ? var.cluster_parameter_group_family
    : "aurora-postgresql${local.pg_major_version}"
  )
  instance_pg_family = (
    var.instance_parameter_group_family != ""
    ? var.instance_parameter_group_family
    : "aurora-postgresql${local.pg_major_version}"
  )
}

###############################################################################
# KMS Key — Aurora encryption at rest
###############################################################################

resource "aws_kms_key" "aurora" {
  description             = "KMS key for Aurora cluster ${var.cluster_identifier}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-aurora-kms"
  })
}

resource "aws_kms_alias" "aurora" {
  name          = "alias/${var.cluster_identifier}-aurora"
  target_key_id = aws_kms_key.aurora.key_id
}

###############################################################################
# Secrets Manager — Aurora master password (auto-rotation every 30 days)
###############################################################################

resource "random_password" "aurora_master" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "aurora_master" {
  name                    = "${var.cluster_identifier}/master-credentials"
  description             = "Aurora master credentials for ${var.cluster_identifier}"
  kms_key_id              = aws_kms_key.aurora.arn
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-master-secret"
  })
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  secret_id = aws_secretsmanager_secret.aurora_master.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.aurora_master.result
    engine   = var.engine
    host     = aws_rds_cluster.this.endpoint
    port     = aws_rds_cluster.this.port
    dbname   = var.database_name
  })
}

###############################################################################
# IAM Role — Enhanced Monitoring
###############################################################################

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.cluster_identifier}-rds-monitoring-role"

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
# Aurora Cluster Parameter Group
###############################################################################

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.cluster_identifier}-cluster-pg"
  family      = local.cluster_pg_family
  description = "Custom cluster parameter group for ${var.cluster_identifier}"

  parameter {
    name  = "shared_preload_libraries"
    value = var.shared_preload_libraries
  }

  parameter {
    name  = "log_statement"
    value = var.log_statement
  }

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement)
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = local.common_tags
}

###############################################################################
# Aurora Instance Parameter Group
###############################################################################

resource "aws_db_parameter_group" "this" {
  name        = "${var.cluster_identifier}-instance-pg"
  family      = local.instance_pg_family
  description = "Custom instance parameter group for ${var.cluster_identifier}"

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
# Aurora Cluster
###############################################################################

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.cluster_identifier
  engine             = var.engine
  engine_version     = var.engine_version
  engine_mode        = "provisioned" # Required for Aurora Serverless v2
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = random_password.aurora_master.result

  # Aurora Serverless v2 — scales between min and max ACUs per instance
  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity_units
    max_capacity = var.max_capacity_units
  }

  db_subnet_group_name            = var.subnet_group_name
  vpc_security_group_ids          = var.security_group_ids
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  # Encryption
  storage_encrypted = true
  kms_key_id        = aws_kms_key.aurora.arn

  # Backup & maintenance
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  # Snapshots
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.cluster_identifier}-final-snapshot"
  copy_tags_to_snapshot     = true

  # Security
  deletion_protection                 = var.deletion_protection
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = var.cloudwatch_log_exports

  # Auto minor version upgrades
  allow_major_version_upgrade = false

  tags = merge(local.common_tags, {
    Name = var.cluster_identifier
  })

  lifecycle {
    ignore_changes = [master_password]
  }
}

###############################################################################
# Aurora Cluster Instances
###############################################################################

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.cluster_identifier}-instance-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless" # Aurora Serverless v2 instance class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_parameter_group_name = aws_db_parameter_group.this.name

  # Enhanced monitoring
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention

  auto_minor_version_upgrade   = true
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_identifier}-instance-${count.index + 1}"
  })
}

###############################################################################
# Auto-scaling for Aurora read replicas
###############################################################################

resource "aws_appautoscaling_target" "aurora_readers" {
  service_namespace  = "rds"
  resource_id        = "cluster:${aws_rds_cluster.this.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  min_capacity       = var.autoscaling_min_replicas
  max_capacity       = var.autoscaling_max_replicas
}

resource "aws_appautoscaling_policy" "aurora_cpu" {
  name               = "${var.cluster_identifier}-cpu-autoscaling"
  service_namespace  = "rds"
  resource_id        = aws_appautoscaling_target.aurora_readers.resource_id
  scalable_dimension = aws_appautoscaling_target.aurora_readers.scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}
