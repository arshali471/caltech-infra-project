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
