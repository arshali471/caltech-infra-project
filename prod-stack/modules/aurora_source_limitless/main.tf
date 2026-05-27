###############################################################################
# modules/aurora_source_limitless — Aurora PostgreSQL Limitless Database
# Uses AWS default cluster parameter group (Limitless restricts custom families).
# Capacity is controlled via aws_rds_shard_group ACU range.
###############################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-aurora-source-limitless-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.name}-aurora-source-limitless-subnet-group" })
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
