# Partial S3 backend — supply the rest at init time:
#
#   terraform init -backend-config=test-backend.hcl
#
# The shared S3 bucket must exist first. Run the bootstrap script once from the
# project root if you haven't already:
#   chmod +x ../scripts/bootstrap-backend.sh && ../scripts/bootstrap-backend.sh

terraform {
  backend "s3" {}
}
