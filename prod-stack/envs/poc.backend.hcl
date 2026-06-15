# Backend configuration for the POC environment.
# Run: terraform init -reconfigure -backend-config=envs/poc.backend.hcl
#
# Uses S3 native locking (use_lockfile=true) — requires Terraform >= 1.10.
# No DynamoDB table needed; the lock file (.tflock) is written alongside the
# state file in the same S3 bucket using S3 conditional writes.
#
# NOTE: the `key` uses the legacy path "caltech/prod/..." (not "caltech/poc/...")
# because this is where the live state file already exists in the bucket.
# Path B = state stays put; the backend.hcl must point at the real S3 location.
bucket       = "caltech-terraform-state-342448511503"
key          = "caltech/prod/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
use_lockfile = true
profile      = "default"
