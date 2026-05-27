###############################################################################
# modules/aurora_source_limitless — Aurora PostgreSQL Limitless Database
#
# WORKAROUND: AWS provider <= v5.100.0 always sends engine_mode="provisioned"
# even when cluster_scalability_type="limitless", which AWS rejects.
# We bypass this by creating the cluster + shard group via AWS CLI through
# null_resource, then expose cluster info via a data source.
#
# Terraform still owns create/destroy lifecycle through triggers + destroy
# provisioners. Drift detection is limited (cluster mutations outside TF
# won't be detected) — acceptable for a single-cluster CDC source.
###############################################################################

locals {
  cluster_id = "${var.name}-aurora-source-limitless"
  shard_id   = "${var.name}-aurora-source-limitless-shard"
}

data "aws_region" "current" {}

resource "aws_db_subnet_group" "this" {
  name       = "${local.cluster_id}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${local.cluster_id}-subnet-group" })
}

# ---- IAM role for RDS Enhanced Monitoring (required by Limitless) ----------

resource "aws_iam_role" "monitoring" {
  name = "${local.cluster_id}-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${local.cluster_id}-monitoring-role" })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ---- Cluster — created via AWS CLI ------------------------------------------

resource "null_resource" "cluster" {
  triggers = {
    cluster_id     = local.cluster_id
    engine_version = var.engine_version
    aws_region     = data.aws_region.current.name
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      if aws rds describe-db-clusters \
           --db-cluster-identifier ${local.cluster_id} \
           --region ${data.aws_region.current.name} >/dev/null 2>&1; then
        echo "Cluster ${local.cluster_id} already exists — skipping create"
      else
        aws rds create-db-cluster \
          --db-cluster-identifier ${local.cluster_id} \
          --engine ${var.engine} \
          --engine-version ${var.engine_version} \
          --cluster-scalability-type limitless \
          --storage-type aurora-iopt1 \
          --master-username ${var.master_username} \
          --master-user-password '${var.master_password}' \
          --db-subnet-group-name ${aws_db_subnet_group.this.name} \
          --vpc-security-group-ids ${var.security_group_id} \
          --kms-key-id ${var.kms_key_arn} \
          --storage-encrypted \
          --enable-performance-insights \
          --performance-insights-kms-key-id ${var.kms_key_arn} \
          --performance-insights-retention-period 7 \
          --monitoring-interval 60 \
          --monitoring-role-arn ${aws_iam_role.monitoring.arn} \
          --enable-cloudwatch-logs-exports postgresql \
          --backup-retention-period ${var.backup_retention_period} \
          --preferred-backup-window ${var.preferred_backup_window} \
          --preferred-maintenance-window ${var.preferred_maintenance_window} \
          ${var.deletion_protection ? "--deletion-protection" : "--no-deletion-protection"} \
          --region ${data.aws_region.current.name}
      fi
      echo "Waiting for cluster to become available..."
      aws rds wait db-cluster-available \
        --db-cluster-identifier ${local.cluster_id} \
        --region ${data.aws_region.current.name}
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      aws rds delete-db-cluster \
        --db-cluster-identifier ${self.triggers.cluster_id} \
        --skip-final-snapshot \
        --region ${self.triggers.aws_region} 2>/dev/null || true
    EOT
  }

  depends_on = [aws_db_subnet_group.this, aws_iam_role_policy_attachment.monitoring]
}

# ---- Shard Group — created via AWS CLI after cluster is ready ---------------

resource "null_resource" "shard_group" {
  triggers = {
    shard_id           = local.shard_id
    cluster_id         = local.cluster_id
    min_acu            = var.min_acu
    max_acu            = var.max_acu
    compute_redundancy = var.compute_redundancy
    aws_region         = data.aws_region.current.name
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -e
      if aws rds describe-db-shard-groups \
           --db-shard-group-identifier ${local.shard_id} \
           --region ${data.aws_region.current.name} >/dev/null 2>&1; then
        echo "Shard group ${local.shard_id} already exists — skipping create"
      else
        aws rds create-db-shard-group \
          --db-shard-group-identifier ${local.shard_id} \
          --db-cluster-identifier ${local.cluster_id} \
          --max-acu ${var.max_acu} \
          --min-acu ${var.min_acu} \
          --compute-redundancy ${var.compute_redundancy} \
          --region ${data.aws_region.current.name}
      fi
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      aws rds delete-db-shard-group \
        --db-shard-group-identifier ${self.triggers.shard_id} \
        --region ${self.triggers.aws_region} 2>/dev/null || true
    EOT
  }

  depends_on = [null_resource.cluster]
}

# ---- Data source — expose cluster info after creation -----------------------

data "aws_rds_cluster" "this" {
  cluster_identifier = local.cluster_id
  depends_on         = [null_resource.cluster]
}
