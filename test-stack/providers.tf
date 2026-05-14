provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "test"
      Project     = var.project
      ManagedBy   = "terraform"
      Stack       = "test-stack"
    }
  }
}
