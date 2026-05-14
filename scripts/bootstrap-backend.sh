#!/usr/bin/env bash
###############################################################################
# scripts/bootstrap-backend.sh
#
# Creates the S3 remote-state bucket and DynamoDB lock table that backend.tf
# requires BEFORE you can run `terraform init`.
#
# Run ONCE per environment:
#   chmod +x scripts/bootstrap-backend.sh
#   AWS_PROFILE=my-profile ./scripts/bootstrap-backend.sh
#
# Requirements:
#   - AWS CLI v2 installed and a profile / environment variable with
#     AdministratorAccess (or S3 + DynamoDB create permissions)
#   - jq installed (brew install jq / apt install jq)
###############################################################################

set -euo pipefail

###############################################################################
# CONFIGURATION — change these if you rename the project or environment
###############################################################################
BUCKET="cultech-terraform-state"
TABLE="cultech-terraform-lock"
REGION="us-west-1"
PROJECT="cultech"
ENVIRONMENT="shared"

###############################################################################
# Helper
###############################################################################
info()  { echo -e "\033[0;36m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

###############################################################################
# Preflight checks
###############################################################################
command -v aws  >/dev/null 2>&1 || die "AWS CLI not found. Install: https://aws.amazon.com/cli/"
command -v jq   >/dev/null 2>&1 || warn "jq not found — JSON pretty-print disabled."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
info "AWS Account : $ACCOUNT_ID"
info "AWS Region  : $REGION"
info "S3 bucket   : $BUCKET"
info "DynamoDB    : $TABLE"
echo ""

###############################################################################
# S3 Bucket — create if absent
###############################################################################
info "Checking S3 bucket..."
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  ok "Bucket '$BUCKET' already exists — skipping create."
else
  info "Creating bucket '$BUCKET'..."
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
  ok "Bucket created."
fi

###############################################################################
# Versioning — required so state history is preserved
###############################################################################
info "Enabling versioning on '$BUCKET'..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
ok "Versioning enabled."

###############################################################################
# Server-side encryption — SSE-S3 (AES-256)
###############################################################################
info "Enabling SSE-S3 encryption on '$BUCKET'..."
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
      "BucketKeyEnabled": true
    }]
  }'
ok "Encryption enabled."

###############################################################################
# Block all public access
###############################################################################
info "Blocking public access on '$BUCKET'..."
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
ok "Public access blocked."

###############################################################################
# Bucket policy — restrict access to this AWS account only
###############################################################################
info "Applying bucket policy (account-only access)..."
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(cat <<-POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyNonTLS",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET}",
        "arn:aws:s3:::${BUCKET}/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    },
    {
      "Sid": "DenyOtherAccounts",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET}",
        "arn:aws:s3:::${BUCKET}/*"
      ],
      "Condition": {
        "StringNotEquals": { "aws:PrincipalAccount": "${ACCOUNT_ID}" }
      }
    }
  ]
}
POLICY
)"
ok "Bucket policy applied."

###############################################################################
# Lifecycle rule — expire non-current versions after 90 days (cost control)
###############################################################################
info "Setting lifecycle rule (expire old state versions after 90 days)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "$BUCKET" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-noncurrent-state-versions",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }]
  }'
ok "Lifecycle rule applied."

###############################################################################
# DynamoDB lock table — create if absent
###############################################################################
info "Checking DynamoDB table '$TABLE'..."
if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" 2>/dev/null | grep -q ACTIVE; then
  ok "Table '$TABLE' already exists — skipping create."
else
  info "Creating DynamoDB table '$TABLE'..."
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION" \
    --tags \
      "Key=Project,Value=${PROJECT}" \
      "Key=Environment,Value=${ENVIRONMENT}" \
      "Key=ManagedBy,Value=bootstrap"
  info "Waiting for DynamoDB table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
  ok "DynamoDB table created and ACTIVE."
fi

###############################################################################
# Enable DynamoDB Point-in-Time Recovery (PITR)
###############################################################################
info "Enabling DynamoDB PITR on '$TABLE'..."
aws dynamodb update-continuous-backups \
  --table-name "$TABLE" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region "$REGION" 2>/dev/null \
  && ok "PITR enabled." || warn "PITR enable failed (may already be enabled)."

###############################################################################
# Done
###############################################################################
echo ""
echo "============================================================"
ok "Bootstrap complete! Backend resources are ready."
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. cd $(pwd)"
echo "  2. terraform init"
echo "  3. terraform plan -out=tfplan"
echo "  4. terraform apply tfplan"
echo ""
