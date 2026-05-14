###############################################################################
# modules/msk — MSK Serverless cluster, SASL/IAM auth, TLS in-transit
###############################################################################

resource "aws_msk_serverless_cluster" "this" {
  cluster_name = "${var.name}-msk"

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-msk", Purpose = "CDC event streaming" })
}
