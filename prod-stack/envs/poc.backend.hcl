# Backend configuration for the POC environment.
# Run: terraform init -reconfigure -backend-config=envs/poc.backend.hcl
#
# Uses S3 native locking (use_lockfile=true) — requires Terraform >= 1.10.
# No DynamoDB table needed; the lock file (.tflock) is written alongside the
# state file in the same S3 bucket using S3 conditional writes.
bucket       = "caltech-terraform-state-342448511503"
key          = "caltech/poc/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
use_lockfile = true
profile      = "default"
