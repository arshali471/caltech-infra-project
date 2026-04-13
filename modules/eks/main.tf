###############################################################################
# modules/eks/main.tf
# Creates: EKS cluster, KMS encryption, OIDC/IRSA, managed node groups,
#          cluster add-ons (vpc-cni, kube-proxy, coredns, ebs-csi-driver)
###############################################################################

locals {
  common_tags = merge(var.tags, {
    Module    = "eks"
    ManagedBy = "terraform"
  })
}

###############################################################################
# KMS key — EKS secrets envelope encryption
###############################################################################

resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster ${var.cluster_name} secrets"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-eks-kms"
  })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

###############################################################################
# IAM Role — EKS Cluster
###############################################################################

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

###############################################################################
# CloudWatch Log Group — EKS control-plane logs
###############################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

###############################################################################
# EKS Cluster
###############################################################################

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.cluster_security_group_id]
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access ? var.cluster_endpoint_public_access_cidrs : null
  }

  enabled_cluster_log_types = var.enable_cluster_log_types

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller,
    aws_cloudwatch_log_group.cluster,
  ]
}

###############################################################################
# OIDC Provider — IRSA (IAM Roles for Service Accounts)
###############################################################################

data "tls_certificate" "cluster" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-oidc-provider"
  })
}

###############################################################################
# IAM Role — Fargate Pod Execution
###############################################################################

resource "aws_iam_role" "fargate_pod_execution" {
  name = "${var.cluster_name}-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution.name
}

# ECR read access so Fargate can pull private images
resource "aws_iam_role_policy_attachment" "fargate_ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.fargate_pod_execution.name
}

###############################################################################
# EKS Fargate Profiles
###############################################################################

# System profile — always created so CoreDNS / kube-proxy can run on Fargate
resource "aws_eks_fargate_profile" "system" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${var.cluster_name}-system"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.subnet_ids

  selector { namespace = "kube-system" }
  selector { namespace = "kube-public" }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-system"
  })

  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution]
}

# Application profiles — user-defined namespace selectors
resource "aws_eks_fargate_profile" "this" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "${var.cluster_name}-${each.key}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = var.subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels != {} ? selector.value.labels : null
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${each.key}"
  })

  depends_on = [aws_iam_role_policy_attachment.fargate_pod_execution]
}

###############################################################################
# EKS Add-ons
###############################################################################

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  # Enable Security Groups for Pods so Fargate pods can use custom SGs
  configuration_values = jsonencode({
    env = {
      ENABLE_POD_ENI          = "true"
      DISABLE_TCP_EARLY_DEMUX = "true"
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags

  # CoreDNS must run on Fargate — system Fargate profile must exist first
  depends_on = [
    aws_eks_fargate_profile.system,
    aws_eks_fargate_profile.this,
  ]
}

# NOTE: aws-ebs-csi-driver is NOT supported on Fargate.
# Use Amazon EFS CSI driver or Amazon S3 CSI driver for persistent storage.
