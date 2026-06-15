# Backend configuration for the DEV environment.
# Run: terraform init -reconfigure -backend-config=envs/dev.backend.hcl
#
# Same S3 bucket as prod (S3 is global — region of bucket doesn't matter for
# state storage), but different `key` so dev/prod state files are isolated.
# Uses S3 native locking (use_lockfile=true) — requires Terraform >= 1.10.
bucket       = "caltech-terraform-state-342448511503"
key          = "caltech/dev/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
use_lockfile = true
profile      = "default"
