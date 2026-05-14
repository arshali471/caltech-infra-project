###############################################################################
# modules/ec2 — single app server in public subnet
# Access: SSM Session Manager only (no open SSH port)
###############################################################################

resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  iam_instance_profile        = var.instance_profile_name
  vpc_security_group_ids      = [var.security_group_id]

  metadata_options {
    http_endpoint               = var.imds_http_endpoint
    http_tokens                 = var.imds_http_tokens
    http_put_response_hop_limit = var.imds_http_put_response_hop_limit
  }

  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_gb
    encrypted             = true
    kms_key_id            = var.ebs_kms_key_arn
    delete_on_termination = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y ${var.java_package} python3-pip git
    pip3 install --upgrade awscli
    cd /opt
    curl -fsSL \
      "https://github.com/aws/aws-msk-iam-auth/releases/download/v${var.msk_iam_auth_version}/aws-msk-iam-auth-${var.msk_iam_auth_version}-all.jar" \
      -o aws-msk-iam-auth.jar
    echo "Bootstrap complete - $$(date)"
  EOF
  )

  tags = merge(var.tags, {
    Name    = "${var.name}-app-server"
    Purpose = "Transaction Simulator + Kafka Consumers"
  })
}
