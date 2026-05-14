###############################################################################
# test-stack/terraform.tfvars
#
# Quick-start testing values — MSK + ElastiCache only, minimal cost.
# Estimated monthly cost: ~$120–$180 USD
#   - MSK Serverless:       ~$60–$100 (idle cluster charge + per-GB throughput)
#   - ElastiCache Serverless: ~$20–$40 (idle + ECPU usage)
#   - NAT Gateway:          ~$35 (fixed + data transfer)
#   - EC2 t3.micro bastion: ~$8
#
# Tear down when done: terraform destroy
###############################################################################

aws_region = "us-west-1"
project    = "cultech"

# Networking — separate CIDR from main project (10.0.0.0/16)
vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["us-west-1a", "us-west-1c"]
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

# ElastiCache — minimum capacity for testing
redis_min_data_storage_gb = 1
redis_max_data_storage_gb = 10
redis_min_ecpu_per_second = 1000
redis_max_ecpu_per_second = 10000

# Bastion
bastion_instance_type = "t3.micro"

tags = {
  Owner       = "platform-team"
  CostCenter  = "engineering"
  Environment = "test"
  Purpose     = "kafka-redis-testing"
}
