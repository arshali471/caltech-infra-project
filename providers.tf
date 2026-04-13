###############################################################################
# Providers
###############################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    })
  }
}

provider "tls" {}

# Kubernetes provider — configured after EKS cluster is created.
# try() guards against empty-string on initial bootstrap before EKS exists.
provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}
