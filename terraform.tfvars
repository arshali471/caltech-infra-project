###############################################################################
# terraform.tfvars — Default values (POC environment, auto-loaded by Terraform)
#
# This file is auto-loaded. It targets the POC environment by default.
# For a specific environment, pass the matching file at plan/apply time:
#
#   POC (default):  terraform plan -var-file=environments/poc.tfvars
#   Dev:            terraform plan -var-file=environments/dev.tfvars
#   UAT:            terraform plan -var-file=environments/uat.tfvars
#   Prod:           terraform plan -var-file=environments/prod.tfvars
#
# BACKEND — init per environment:
#   terraform init -backend-config=environments/poc-backend.hcl  -reconfigure
#   terraform init -backend-config=environments/prod-backend.hcl -reconfigure
#
# ONE-TIME bootstrap (creates shared S3 bucket + DynamoDB table):
#   chmod +x scripts/bootstrap-backend.sh && ./scripts/bootstrap-backend.sh
###############################################################################

aws_region  = "us-west-1"
environment = "poc"
project     = "cultech"

# --- VPC ---
vpc_cidr                    = "10.0.0.0/16"
availability_zones          = ["us-west-1a", "us-west-1c"]
public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs     = ["10.0.20.0/24", "10.0.21.0/24"]
single_nat_gateway          = true # One NAT GW saves ~$35/month in POC
enable_nat_gateway          = true
vpc_flow_log_retention_days = 7

# --- EKS Fargate ---
eks_cluster_version         = "1.32"
eks_endpoint_public_access  = true # Expose API server for POC convenience
eks_endpoint_private_access = true
eks_enable_irsa             = true
eks_cluster_log_types       = ["api", "audit"]

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
aurora_db_name                  = "appdb"
aurora_master_username          = "dbadmin"
aurora_instance_count           = 1
aurora_min_capacity_units       = 0.5
aurora_max_capacity_units       = 4
aurora_autoscaling_max_replicas = 1

# --- Aurora PostgreSQL Serverless v2 (CDC Source / Debezium) ---
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
alb_deletion_protection = false # Easy teardown in POC
alb_idle_timeout        = 60
alb_enable_waf          = false # WAF adds ~$25+/month; skip for POC

# --- Database operational parameters ---
db_backup_retention_days          = 1
db_performance_insights_retention = 7
db_monitoring_interval            = 60
kms_deletion_window               = 7
secret_recovery_window            = 7

tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "cultech"
  Environment = "poc"
}
