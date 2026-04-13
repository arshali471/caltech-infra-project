# UAT environment — Terraform remote state configuration
# Usage: terraform init -backend-config=environments/uat-backend.hcl -reconfigure

bucket         = "cultech-terraform-state"
key            = "cultech/uat/terraform.tfstate"
region         = "us-west-1"
encrypt        = true
dynamodb_table = "cultech-terraform-lock"
