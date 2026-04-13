###############################################################################
# environments/prod.tfvars — Cultech Production Environment
#
# Purpose : Live production traffic. Full HA topology with maximum capacity
#           settings tuned for 1,000,000 requests per second.
#
# Usage:
#   terraform init  -backend-config=environments/prod-backend.hcl -reconfigure
#   terraform plan  -var-file=environments/prod.tfvars  -out=tfplan-prod
#   terraform apply tfplan-prod
#
# CRITICAL: Requires approved change ticket before apply.
#
# Estimated monthly cost: ~$8,000–$15,000 USD (traffic-dependent)
# Scale target: 1,000,000 requests per second sustained
###############################################################################

aws_region  = "us-west-1"
environment = "prod"
project     = "cultech"

# --- VPC ---
# /20 app = 4091 IPs per AZ (EKS Fargate: 1 ENI per pod; hundreds needed)
# /22 db  = 1022 IPs per AZ (Aurora + Redis serverless ENIs)
vpc_cidr                    = "10.0.0.0/16"
availability_zones          = ["us-west-1a", "us-west-1c"]
public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs    = ["10.0.16.0/20", "10.0.32.0/20"]
private_db_subnet_cidrs     = ["10.0.48.0/22", "10.0.52.0/22"]
single_nat_gateway          = false # 2 NAT GWs: one per AZ — eliminates cross-AZ latency
enable_nat_gateway          = true
vpc_flow_log_retention_days = 90

# --- EKS Fargate ---
# 1.32 = latest stable (April 2026). Standard support active.
eks_cluster_version         = "1.32"
eks_endpoint_public_access  = false # API server only reachable inside VPC
eks_endpoint_private_access = true
eks_enable_irsa             = true
eks_cluster_log_types       = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

eks_fargate_profiles = {
  apps = {
    selectors = [
      { namespace = "default", labels = {} },
      { namespace = "production", labels = {} },
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
# 128 ACU = AWS maximum (256 GiB RAM). 3 instances: 1 writer + 2 readers.
aurora_db_name                  = "appdb"
aurora_master_username          = "dbadmin"
aurora_instance_count           = 3
aurora_min_capacity_units       = 2
aurora_max_capacity_units       = 128
aurora_autoscaling_max_replicas = 10

# --- Aurora PostgreSQL Serverless v2 (CDC Source — Debezium) ---
rds_db_name            = "sourcedb"
rds_master_username    = "dbadmin"
rds_instance_count     = 2
rds_min_capacity_units = 1
rds_max_capacity_units = 64

# --- ElastiCache Serverless Redis ---
# 5M ECPU/s: 1M RPS × ~5 Redis ops = 5M ECPU/s. AWS max = 15M ECPU/s.
# 1 TB cache: session store + hot data for 1M concurrent users.
redis_major_engine_version = "7"
redis_min_data_storage_gb  = 10
redis_max_data_storage_gb  = 1000
redis_min_ecpu_per_second  = 10000
redis_max_ecpu_per_second  = 5000000

# --- ALB ---
alb_deletion_protection = true
alb_idle_timeout        = 120  # Handles long-running API + streaming connections
alb_enable_waf          = true # OWASP rules + SQLi + rate-limiting

# --- Database operational parameters ---
db_backup_retention_days          = 30  # 30 days automated backup history
db_performance_insights_retention = 731 # 2 years Performance Insights (paid)
db_monitoring_interval            = 1   # 1-second enhanced monitoring (maximum)
kms_deletion_window               = 30  # Maximum protection window
secret_recovery_window            = 30  # Maximum protection window

# --- SSL (uncomment and set ARN after ACM certificate is issued) ---
# alb_ssl_certificate_arn = "arn:aws:acm:us-west-1:ACCOUNT_ID:certificate/CERT_ID"

tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Terraform   = "true"
  Project     = "cultech"
  Environment = "prod"
}
