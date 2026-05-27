###############################################################################
# modules/aurora_source_limitless — Aurora PostgreSQL Limitless Database
# Logical replication enabled (for Debezium CDC) on the limitless variant.
# Uses aws_rds_shard_group for capacity (instead of serverless v2 scaling).
###############################################################################

locals {
  pg_major_version = split(".", var.engine_version)[0]
  pg_family        = "${var.engine}-limitless${local.pg_major_version}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-aurora-source-limitless-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-aurora-source-limitless-subnet-group" })
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-aurora-source-limitless-pg"
  family      = local.pg_family
  description = "Logical replication enabled for Debezium CDC on Limitless"

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

  tags = merge(var.tags, { Name = "${var.name}-aurora-source-limitless-pg" })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.name}-aurora-source-limitless"
  engine                          = var.engine
  engine_mode                     = "provisioned"
  engine_version                  = var.engine_version
  cluster_scalability_type        = "limitless"
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
  final_snapshot_identifier       = "${var.name}-aurora-source-limitless-final"
  deletion_protection             = var.deletion_protection
  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports

  tags = merge(var.tags, { Name = "${var.name}-aurora-source-limitless", Role = "CDC Source Limitless" })

  lifecycle { ignore_changes = [master_password] }
}

resource "aws_rds_shard_group" "this" {
  db_cluster_identifier     = aws_rds_cluster.this.id
  db_shard_group_identifier = "${var.name}-aurora-source-limitless-shard"
  min_acu                   = var.min_acu
  max_acu                   = var.max_acu
  compute_redundancy        = var.compute_redundancy
  publicly_accessible       = false

  tags = merge(var.tags, { Name = "${var.name}-aurora-source-limitless-shard" })
}
