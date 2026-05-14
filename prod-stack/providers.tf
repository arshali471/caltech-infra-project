provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = merge(var.tags, {
      Environment = var.environment
      Project     = var.project
      ManagedBy   = "terraform"
    })
  }
}
