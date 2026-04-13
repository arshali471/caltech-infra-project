###############################################################################
# environments/dev.tfvars — Cultech Development Environment
#
# Purpose : Active development. Developers deploy feature branches here for
#           integration testing against real AWS services.
#
# Usage:
#   terraform init  -backend-config=environments/dev-backend.hcl -reconfigure
#   terraform plan  -var-file=environments/dev.tfvars  -out=tfplan-dev
#   terraform apply tfplan-dev
#
# Estimated monthly cost: ~$600–$800 USD
# Scale target: ~1,000 concurrent users / integration test loads
###############################################################################

aws_region  = "us-west-1"
environment = "dev"
project     = "cultech"

# --- VPC ---
vpc_cidr                    = "10.0.0.0/16"
availability_zones          = ["us-west-1a", "us-west-1c"]
public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs    = ["10.0.10.0/23", "10.0.12.0/23"] # /23 = 510 IPs per AZ
private_db_subnet_cidrs     = ["10.0.20.0/24", "10.0.21.0/24"]
single_nat_gateway          = true # Still single NAT in dev (save cost)
enable_nat_gateway          = true
vpc_flow_log_retention_days = 14

# --- EKS Fargate ---
eks_cluster_version         = "1.32"
eks_endpoint_public_access  = true # Developers need direct API access
eks_endpoint_private_access = true
eks_enable_irsa             = true
eks_cluster_log_types       = ["api", "audit", "authenticator"]

eks_fargate_profiles = {
  apps = {
    selectors = [
      { namespace = "default", labels = {} },
      { namespace = "dev", labels = {} },
      { namespace = "kube-system", labels = {} }
    ]
  }
  debezium = {
    selectors = [{ namespace = "debezium", labels = {} }]
  }
  monitoring = {
    selectors = [{ namespace = "monitoring", labels = {} }]
  }
}

# --- Aurora PostgreSQL Serverless v2 (Primary DB) ---
aurora_db_name                  = "appdb"
aurora_master_username          = "dbadmin"
aurora_instance_count           = 1
aurora_min_capacity_units       = 0.5
aurora_max_capacity_units       = 8
aurora_autoscaling_max_replicas = 2

# --- Aurora PostgreSQL Serverless v2 (CDC Source — Debezium) ---
rds_db_name            = "sourcedb"
rds_master_username    = "dbadmin"
rds_instance_count     = 1
rds_min_capacity_units = 0.5
rds_max_capacity_units = 4

# --- ElastiCache Serverless Redis ---
redis_major_engine_version = "7"
redis_min_data_storage_gb  = 1
redis_max_data_storage_gb  = 20
redis_min_ecpu_per_second  = 1000
redis_max_ecpu_per_second  = 50000

# --- ALB ---
alb_deletion_protection = false
alb_idle_timeout        = 60
alb_enable_waf          = false

# --- Database operational parameters ---
db_backup_retention_days          = 7
db_performance_insights_retention = 7
db_monitoring_interval            = 30
kms_deletion_window               = 7
secret_recovery_window            = 7

tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "cultech"
  Environment = "dev"
}
