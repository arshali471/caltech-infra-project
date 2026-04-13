###############################################################################
# modules/eks/outputs.tf
###############################################################################

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.this.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider (used for IRSA)"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.cluster[0].arn : null
}

output "fargate_pod_execution_role_arn" {
  description = "ARN of the Fargate pod execution IAM role"
  value       = aws_iam_role.fargate_pod_execution.arn
}

output "fargate_profile_names" {
  description = "List of all Fargate profile names (system + app profiles)"
  value = concat(
    [aws_eks_fargate_profile.system.fargate_profile_name],
    [for p in aws_eks_fargate_profile.this : p.fargate_profile_name]
  )
}

output "kms_key_arn" {
  description = "ARN of the KMS key for EKS secrets encryption"
  value       = aws_kms_key.eks.arn
}
