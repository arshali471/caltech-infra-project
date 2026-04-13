###############################################################################
# Terraform Remote State — Partial S3 Backend
#
# Configuration is provided per-environment at `terraform init` time:
#
#   terraform init -backend-config=environments/poc-backend.hcl   -reconfigure
#   terraform init -backend-config=environments/dev-backend.hcl   -reconfigure
#   terraform init -backend-config=environments/uat-backend.hcl   -reconfigure
#   terraform init -backend-config=environments/prod-backend.hcl  -reconfigure
#
# Before running init for ANY environment, create the shared backend
# infrastructure once:
#   chmod +x scripts/bootstrap-backend.sh && ./scripts/bootstrap-backend.sh
###############################################################################

terraform {
  backend "s3" {}
}
