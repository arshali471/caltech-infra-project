# Backend configuration for the DEV environment.
# Run: terraform init -reconfigure -backend-config=envs/dev.backend.hcl
#
# Client-shared state bucket: tfstate-imss-shared-342448511503-us-west-2
#   • Bucket lives in us-west-2 (S3 is globally addressable — fine for resources
#     deployed in us-east-2)
#   • State file lives under caltech/dev/ so it is isolated from POC and any
#     other project sharing the bucket
#   • Lock file is auto-managed at caltech/dev/terraform.tfstate.tflock by S3
#     conditional writes (no DynamoDB needed; requires Terraform >= 1.10)
#
# Override the profile via CLI flag if the client uses a different one, e.g.:
#   terraform init -backend-config=envs/dev.backend.hcl \
#                  -backend-config="profile=<client-profile>"

bucket       = "tfstate-imss-shared-342448511503-us-west-2"
key          = "caltech/dev/terraform.tfstate"
region       = "us-west-2"
encrypt      = true
use_lockfile = true
profile      = "default"
