###############################################################################
# modules/aurora_sink — Aurora PostgreSQL Serverless v2, consumer target
# Parameter group family is derived from the major engine version automatically.
###############################################################################

locals {
  pg_major_version = split(".", var.engine_version)[0]
  pg_family        = "${var.engine}${local.pg_major_version}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-aurora-sink-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-aurora-sink-subnet-group" })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.name}-aurora-sink"
  engine                          = var.engine
  engine_mode                     = "provisioned"
  engine_version                  = var.engine_version
  database_name                   = var.db_name
  master_username                 = var.master_username
  master_password                 = var.master_password
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [var.security_group_id]
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = "${var.name}-aurora-sink-final"
  deletion_protection             = var.deletion_protection
  enabled_cloudwatch_logs_exports = var.cloudwatch_logs_exports

  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }

  tags = merge(var.tags, { Name = "${var.name}-aurora-sink", Role = "PostgreSQL Sink" })

  lifecycle { ignore_changes = [master_password] }
}

resource "aws_rds_cluster_instance" "this" {
  identifier           = "${var.name}-aurora-sink-1"
  cluster_identifier   = aws_rds_cluster.this.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.this.engine
  engine_version       = aws_rds_cluster.this.engine_version
  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = false
  tags                 = merge(var.tags, { Name = "${var.name}-aurora-sink-1" })
}
