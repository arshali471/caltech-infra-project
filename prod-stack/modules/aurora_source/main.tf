###############################################################################
# modules/aurora_source — Aurora PostgreSQL Serverless v2, Debezium CDC source
# Parameter group family is derived from the major engine version automatically.
###############################################################################

locals {
  pg_major_version = split(".", var.engine_version)[0]
  pg_family        = "${var.engine}${local.pg_major_version}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-aurora-source-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-aurora-source-subnet-group" })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-aurora-source-pg"
  family      = local.pg_family
  description = "Logical replication enabled for Debezium CDC"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_replication_slots"
    value        = tostring(var.max_replication_slots)
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "max_wal_senders"
    value        = tostring(var.max_wal_senders)
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "wal_sender_timeout"
    value        = tostring(var.wal_sender_timeout_ms)
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, { Name = "${var.name}-aurora-source-pg" })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.name}-aurora-source"
  engine                          = var.engine
  engine_mode                     = "provisioned"
  engine_version                  = var.engine_version
  database_name                   = var.db_name
  master_username                 = var.master_username
  master_password                 = var.master_password
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.security_group_id]
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = "${var.name}-aurora-source-final"
  deletion_protection             = var.deletion_protection
  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }

  tags = merge(var.tags, { Name = "${var.name}-aurora-source", Role = "CDC Source" })

  lifecycle { ignore_changes = [master_password] }
}

resource "aws_rds_cluster_instance" "this" {
  identifier           = "${var.name}-aurora-source-1"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false
  tags                 = merge(var.tags, { Name = "${var.name}-aurora-source-1" })
}
