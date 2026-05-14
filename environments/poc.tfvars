###############################################################################
# environments/poc.tfvars — Cultech POC Environment (Option 2: EC2-based)
#
# Architecture: EC2 Transaction Simulator → Aurora → Debezium → MSK →
#               Redis/PostgreSQL Sink Consumers → ElastiCache + RDS →
#               Librechat EC2 (public)
#
# Usage:
#   terraform init  -backend-config=environments/poc-backend.hcl -reconfigure
#   terraform plan  -var-file=environments/poc.tfvars  -out=tfplan-poc
#   terraform apply tfplan-poc
#   terraform destroy -var-file=environments/poc.tfvars
#
# Estimated monthly cost: ~$400–$550 USD
###############################################################################

aws_region  = "us-west-2"
environment = "poc"
project     = "cultech"

# --- VPC ---
vpc_cidr                    = "10.0.0.0/16"
availability_zones          = ["us-west-2a", "us-west-2b"]
public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
private_db_subnet_cidrs     = ["10.0.20.0/24", "10.0.21.0/24"]
single_nat_gateway          = true
enable_nat_gateway          = true
vpc_flow_log_retention_days = 7

# --- EC2 Application Instances ---
ec2_instance_types = {
  transaction_sim = "t3.small"
  debezium        = "t3.medium"
  redis_sink      = "t3.small"
  postgres_sink   = "t3.small"
  librechat       = "t3.small"
}

# --- Aurora PostgreSQL (Source / Primary DB) ---
aurora_db_name                  = "appdb"
aurora_master_username          = "dbadmin"
aurora_instance_count           = 1
aurora_min_capacity_units       = 0.5
aurora_max_capacity_units       = 4
aurora_autoscaling_max_replicas = 1

# --- RDS PostgreSQL (CDC Source + Sink DB) ---
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
