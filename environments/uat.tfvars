###############################################################################
# environments/uat.tfvars — Cultech UAT / Staging Environment
#
# Purpose : User Acceptance Testing. Near-prod topology, used for performance
#           testing, regression, and sign-off before production promotion.
#
# Usage:
#   terraform init  -backend-config=environments/uat-backend.hcl -reconfigure
#   terraform plan  -var-file=environments/uat.tfvars  -out=tfplan-uat
#   terraform apply tfplan-uat
#
# Estimated monthly cost: ~$1,200–$1,600 USD
# Scale target: ~50,000–100,000 concurrent users / load test baseline
###############################################################################

aws_region  = "us-west-1"
environment = "uat"
project     = "cultech"

# --- VPC ---
# /21 = 2046 IPs per AZ — enough for UAT pod counts + headroom
vpc_cidr                    = "10.0.0.0/16"
availability_zones          = ["us-west-1a", "us-west-1c"]
public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs    = ["10.0.8.0/21", "10.0.16.0/21"]  # 2046 IPs per AZ
private_db_subnet_cidrs     = ["10.0.24.0/23", "10.0.26.0/23"] # 510 IPs per AZ
single_nat_gateway          = false                            # HA: one NAT GW per AZ (mirrors production)
enable_nat_gateway          = true
vpc_flow_log_retention_days = 30

# --- EKS Fargate ---
eks_cluster_version         = "1.32"
eks_endpoint_public_access  = false # Locked down like production
eks_endpoint_private_access = true
eks_enable_irsa             = true
eks_cluster_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

eks_fargate_profiles = {
  apps = {
    selectors = [
      { namespace = "default", labels = {} },
      { namespace = "uat", labels = {} },
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
aurora_instance_count           = 2 # Writer + 1 reader for read-scale testing
aurora_min_capacity_units       = 1
aurora_max_capacity_units       = 32
aurora_autoscaling_max_replicas = 4

# --- Aurora PostgreSQL Serverless v2 (CDC Source — Debezium) ---
rds_db_name            = "sourcedb"
rds_master_username    = "dbadmin"
rds_instance_count     = 2 # HA — mirrors production
rds_min_capacity_units = 0.5
rds_max_capacity_units = 16

# --- ElastiCache Serverless Redis ---
redis_major_engine_version = "7"
redis_min_data_storage_gb  = 5
redis_max_data_storage_gb  = 100
redis_min_ecpu_per_second  = 5000
redis_max_ecpu_per_second  = 500000

# --- ALB ---
alb_deletion_protection = true
alb_idle_timeout        = 120
alb_enable_waf          = true # WAF enabled in UAT to validate security rules

# --- Database operational parameters ---
db_backup_retention_days          = 14
db_performance_insights_retention = 7 # Free tier
db_monitoring_interval            = 5
kms_deletion_window               = 14
secret_recovery_window            = 14

tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "cultech"
  Environment = "uat"
}
