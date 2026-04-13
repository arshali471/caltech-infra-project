###############################################################################
# Root main.tf — Orchestrates all modules
###############################################################################

locals {
  name = "${var.project}-${var.environment}"
}

# ============================================================================
# VPC
# ============================================================================

module "vpc" {
  source = "./modules/vpc"

  environment              = var.environment
  project                  = var.project
  region                   = var.aws_region
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  enable_nat_gateway       = var.enable_nat_gateway
  single_nat_gateway       = var.single_nat_gateway
  enable_flow_logs         = true
  flow_log_retention_days  = var.vpc_flow_log_retention_days
  tags                     = var.tags
}

# ============================================================================
# Application Load Balancer (Public Subnet)
# ============================================================================

module "alb" {
  source = "./modules/alb"

  name                = local.name
  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  security_group_id   = module.vpc.alb_security_group_id
  deletion_protection = var.alb_deletion_protection
  ssl_certificate_arn = var.alb_ssl_certificate_arn
  idle_timeout        = var.alb_idle_timeout
  enable_waf          = var.alb_enable_waf
  tags                = var.tags
}

# ============================================================================
# EKS Cluster (App Subnet)
# ============================================================================

module "eks" {
  source = "./modules/eks"

  cluster_name                         = "${local.name}-eks"
  cluster_version                      = var.eks_cluster_version
  vpc_id                               = module.vpc.vpc_id
  subnet_ids                           = module.vpc.private_app_subnet_ids
  cluster_security_group_id            = module.vpc.eks_cluster_security_group_id
  node_security_group_id               = module.vpc.eks_pods_security_group_id
  fargate_profiles                     = var.eks_fargate_profiles
  enable_cluster_log_types             = var.eks_cluster_log_types
  cluster_endpoint_private_access      = var.eks_endpoint_private_access
  cluster_endpoint_public_access       = var.eks_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.eks_public_access_cidrs
  enable_irsa                          = var.eks_enable_irsa
  environment                          = var.environment
  tags                                 = var.tags
}

# ============================================================================
# MSK — Managed Kafka (App Subnet)
# ============================================================================

module "msk" {
  source = "./modules/msk"

  cluster_name       = "${local.name}-kafka"
  environment        = var.environment
  subnet_ids         = module.vpc.private_app_subnet_ids
  security_group_ids = [module.vpc.msk_security_group_id]
  tags               = var.tags
}

# ============================================================================
# Aurora PostgreSQL (DB Subnet)
# ============================================================================

module "aurora" {
  source = "./modules/aurora"

  cluster_identifier = "${local.name}-aurora"
  environment        = var.environment
  database_name      = var.aurora_db_name
  master_username    = var.aurora_master_username
  instance_count     = var.aurora_instance_count
  min_capacity_units = var.aurora_min_capacity_units
  max_capacity_units = var.aurora_max_capacity_units
  subnet_group_name  = module.vpc.db_subnet_group_name
  security_group_ids = [module.vpc.aurora_security_group_id]

  backup_retention_period        = var.db_backup_retention_days
  performance_insights_retention = var.db_performance_insights_retention
  monitoring_interval            = var.db_monitoring_interval
  kms_deletion_window_in_days    = var.kms_deletion_window
  secret_recovery_window_in_days = var.secret_recovery_window
  autoscaling_max_replicas       = var.aurora_autoscaling_max_replicas

  tags = var.tags
}

# ============================================================================
# RDS PostgreSQL — Debezium CDC source (DB Subnet)
# ============================================================================

module "rds" {
  source = "./modules/rds"

  identifier         = "${local.name}-postgres"
  environment        = var.environment
  database_name      = var.rds_db_name
  master_username    = var.rds_master_username
  instance_count     = var.rds_instance_count
  min_capacity_units = var.rds_min_capacity_units
  max_capacity_units = var.rds_max_capacity_units
  subnet_group_name  = module.vpc.db_subnet_group_name
  security_group_ids = [module.vpc.rds_security_group_id]

  backup_retention_period        = var.db_backup_retention_days
  performance_insights_retention = var.db_performance_insights_retention
  monitoring_interval            = var.db_monitoring_interval
  kms_deletion_window_in_days    = var.kms_deletion_window
  secret_recovery_window_in_days = var.secret_recovery_window

  tags = var.tags
}

# ============================================================================
# ElastiCache Redis (DB Subnet)
# ============================================================================

module "elasticache" {
  source = "./modules/elasticache"

  cluster_id           = "${local.name}-redis"
  environment          = var.environment
  major_engine_version = var.redis_major_engine_version
  max_data_storage_gb  = var.redis_max_data_storage_gb
  min_data_storage_gb  = var.redis_min_data_storage_gb
  max_ecpu_per_second  = var.redis_max_ecpu_per_second
  min_ecpu_per_second  = var.redis_min_ecpu_per_second
  subnet_ids           = module.vpc.private_db_subnet_ids
  security_group_ids   = [module.vpc.elasticache_security_group_id]
  tags                 = var.tags
}
