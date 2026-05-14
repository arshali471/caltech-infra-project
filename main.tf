###############################################################################
# Root main.tf — Orchestrates all modules
# Architecture: Option 2 (POC) — EC2-based, us-west-2
#
# Data flow:
#   Caltech 8K transactions
#     → EC2 Transaction Simulator
#     → Aurora PostgreSQL (source DB)
#     → EC2 Debezium CDC
#     → MSK Kafka
#     → EC2 Redis Sink      → ElastiCache Redis
#     → EC2 PostgreSQL Sink → RDS PostgreSQL (sink DB)
#     → EC2 Librechat (public-facing UI)
###############################################################################

locals {
  name = "${var.project}-${var.environment}"

  # MSK IAM policy shared by Debezium, Redis Sink, and PostgreSQL Sink
  msk_producer_consumer_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterConnect"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeCluster",
        ]
        Resource = module.msk.cluster_arn
      },
      {
        Sid    = "MSKTopics"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DeleteTopic",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:AlterTopicDynamicConfiguration",
        ]
        Resource = "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${local.name}-kafka/*/*"
      },
      {
        Sid    = "MSKGroups"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:DeleteGroup",
        ]
        Resource = "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:group/${local.name}-kafka/*/*"
      },
      {
        Sid      = "MSKDescribe"
        Effect   = "Allow"
        Action   = ["kafka:DescribeClusterV2", "kafka:GetBootstrapBrokers"]
        Resource = "*"
      }
    ]
  })
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
# MSK Serverless — Kafka (App Subnet)
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
# Aurora PostgreSQL — Source / Primary DB (DB Subnet)
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
# RDS PostgreSQL — Debezium CDC Source + Sink DB (DB Subnet)
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
# ElastiCache Serverless Redis (DB Subnet)
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

# ============================================================================
# EC2 — Transaction Simulator
# Simulates Caltech 8K transactions → writes to Aurora PostgreSQL
# ============================================================================

module "ec2_transaction_sim" {
  source = "./modules/ec2"

  name          = "${local.name}-transaction-sim"
  role          = "transaction-simulator"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_app_subnet_ids[0]
  instance_type = var.ec2_instance_types["transaction_sim"]
  tags          = var.tags
}

# ============================================================================
# EC2 — Debezium CDC
# Reads Aurora CDC WAL → publishes change events to MSK Kafka (SASL/IAM)
# ============================================================================

module "ec2_debezium" {
  source = "./modules/ec2"

  name          = "${local.name}-debezium"
  role          = "debezium-cdc"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_app_subnet_ids[0]
  instance_type = var.ec2_instance_types["debezium"]
  inline_policy = local.msk_producer_consumer_policy
  tags          = var.tags
}

# ============================================================================
# EC2 — Redis Sink Consumer
# Reads from MSK Kafka → writes to ElastiCache Redis
# ============================================================================

module "ec2_redis_sink" {
  source = "./modules/ec2"

  name          = "${local.name}-redis-sink"
  role          = "redis-sink-consumer"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_app_subnet_ids[0]
  instance_type = var.ec2_instance_types["redis_sink"]
  inline_policy = local.msk_producer_consumer_policy
  tags          = var.tags
}

# ============================================================================
# EC2 — PostgreSQL Sink Consumer
# Reads from MSK Kafka → writes to RDS PostgreSQL sink DB
# ============================================================================

module "ec2_postgres_sink" {
  source = "./modules/ec2"

  name          = "${local.name}-postgres-sink"
  role          = "postgres-sink-consumer"
  vpc_id        = module.vpc.vpc_id
  subnet_id     = module.vpc.private_app_subnet_ids[0]
  instance_type = var.ec2_instance_types["postgres_sink"]
  inline_policy = local.msk_producer_consumer_policy
  tags          = var.tags
}

# ============================================================================
# EC2 — Librechat (public-facing UI)
# Reads from Redis + RDS → serves the Librechat web interface to end users
# ============================================================================

module "ec2_librechat" {
  source = "./modules/ec2"

  name                = "${local.name}-librechat"
  role                = "librechat"
  vpc_id              = module.vpc.vpc_id
  subnet_id           = module.vpc.public_subnet_ids[0]
  instance_type       = var.ec2_instance_types["librechat"]
  associate_public_ip = true

  ingress_rules = [
    {
      description = "Librechat UI (HTTP)"
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  tags = var.tags
}
