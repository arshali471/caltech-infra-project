###############################################################################
# environments/poc.tfvars — Cultech POC Environment
#
# Purpose : Proof-of-Concept. Used to demonstrate the full architecture,
#           validate connectivity, and get manager/stakeholder sign-off.
#
# Usage:
#   terraform init  -backend-config=environments/poc-backend.hcl -reconfigure
#   terraform plan  -var-file=environments/poc.tfvars  -out=tfplan-poc
#   terraform apply tfplan-poc
#   terraform destroy -var-file=environments/poc.tfvars   # easy teardown
#
# Estimated monthly cost: ~$350–$500 USD
# Scale target: Functional validation, NOT load tested
###############################################################################

aws_region  = "us-west-1"
environment = "poc"
project     = "cultech"

# --- VPC ---
# /24 = 251 usable IPs per subnet — sufficient for POC pod counts
vpc_cidr                    = "10.0.0.0/16"
availability_zones          = ["us-west-1a", "us-west-1c"]
public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs     = ["10.0.20.0/24", "10.0.21.0/24"]
single_nat_gateway          = true # 1 NAT GW saves ~$35/month vs HA pair
enable_nat_gateway          = true
vpc_flow_log_retention_days = 7

# --- EKS Fargate ---
eks_cluster_version         = "1.32"
eks_endpoint_public_access  = true # Expose API server endpoint for easy POC access
eks_endpoint_private_access = true
eks_enable_irsa             = true
eks_cluster_log_types       = ["api", "audit"] # Minimal — reduces CW cost

eks_fargate_profiles = {
  apps = {
    selectors = [
      { namespace = "default", labels = {} },
      { namespace = "poc", labels = {} },
      { namespace = "kube-system", labels = {} }
    ]
  }
  debezium = {
    selectors = [{ namespace = "debezium", labels = {} }]
  }
}

# --- Aurora PostgreSQL Serverless v2 (Primary DB) ---
# 1 instance (writer only), low ACU cap — validates schema/query behaviour
aurora_db_name                  = "appdb"
aurora_master_username          = "dbadmin"
aurora_instance_count           = 1
aurora_min_capacity_units       = 0.5
aurora_max_capacity_units       = 4
aurora_autoscaling_max_replicas = 1

# --- Aurora PostgreSQL Serverless v2 (CDC Source — Debezium) ---
rds_db_name            = "sourcedb"
rds_master_username    = "dbadmin"
rds_instance_count     = 1
rds_min_capacity_units = 0.5
rds_max_capacity_units = 2

# --- ElastiCache Serverless Redis ---
redis_major_engine_version = "7"
redis_min_data_storage_gb  = 1
redis_max_data_storage_gb  = 10
redis_min_ecpu_per_second  = 1000
redis_max_ecpu_per_second  = 10000

# --- ALB ---
alb_deletion_protection = false # Allow destroy without force — POC is temporary
alb_idle_timeout        = 60
alb_enable_waf          = false # WAF adds $25+/month; not needed for POC

# --- Database operational parameters ---
db_backup_retention_days          = 1  # Minimum — POC data is disposable
db_performance_insights_retention = 7  # Free tier (7 days)
db_monitoring_interval            = 60 # Least-frequent monitoring
kms_deletion_window               = 7  # Minimum waiting period
secret_recovery_window            = 7  # Minimum recovery window

tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "cultech"
  Environment = "poc"
}
