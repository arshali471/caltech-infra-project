###############################################################################
# modules/msk/main.tf
# Creates: Amazon MSK Serverless cluster
#
# MSK Serverless fully manages:
#   - Broker scaling (unlimited throughput, auto-scales to demand)
#   - Storage (scales automatically, no EBS volumes to provision)
#   - Replication (managed by AWS, always HA across AZs)
#   - Encryption at rest AND in transit (AWS-managed keys, always on)
#   - Kafka version upgrades
#
# Only configurable: VPC placement and SASL/IAM client authentication.
# No custom broker.properties, no instance types, no KMS key required.
###############################################################################

locals {
  common_tags = merge(var.tags, {
    Module    = "msk"
    ManagedBy = "terraform"
  })
}

###############################################################################
# MSK Serverless Cluster
###############################################################################

resource "aws_msk_serverless_cluster" "this" {
  cluster_name = var.cluster_name

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  # MSK Serverless only supports SASL/IAM authentication.
  # Clients (Debezium, application pods) must assume an IAM role
  # and sign requests using AWS Signature v4. Use IRSA for EKS pods.
  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })
}
