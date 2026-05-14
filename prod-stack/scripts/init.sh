#!/usr/bin/env bash
###############################################################################
# prod-stack/scripts/init.sh
#
# Creates the S3 state bucket + DynamoDB lock table, then runs
# terraform init and terraform validate automatically.
#
# AWS credential resolution order (first match wins):
#   1. --profile <name>  flag passed to this script
#   2. AWS_PROFILE       environment variable
#   3. AWS_DEFAULT_PROFILE environment variable
#   4. AWS environment variables (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
#   5. ~/.aws/credentials [default] profile
#   6. EC2 / ECS instance metadata (IAM role)
#
# Usage:
#   chmod +x scripts/init.sh
#   ./scripts/init.sh                          # auto-detect credentials
#   ./scripts/init.sh --profile caltect-account
#   AWS_PROFILE=staging ./scripts/init.sh
###############################################################################

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ── Parse arguments ───────────────────────────────────────────────────────────
PROFILE_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile|-p)
      PROFILE_FLAG="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--profile <aws-profile-name>]"
      exit 0
      ;;
    *)
      error "Unknown argument: $1  (use --profile <name> or set AWS_PROFILE)"
      ;;
  esac
done

# ── Resolve AWS profile / credentials ────────────────────────────────────────
# Priority: --profile flag > AWS_PROFILE env > AWS_DEFAULT_PROFILE env >
#           AWS_ACCESS_KEY_ID env vars > ~/.aws default > instance metadata
resolve_aws_identity() {
  if [[ -n "${PROFILE_FLAG}" ]]; then
    export AWS_PROFILE="${PROFILE_FLAG}"
    CRED_SOURCE="--profile ${PROFILE_FLAG}"
  elif [[ -n "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE="${AWS_PROFILE}"
    CRED_SOURCE="AWS_PROFILE=${AWS_PROFILE}"
  elif [[ -n "${AWS_DEFAULT_PROFILE:-}" ]]; then
    export AWS_PROFILE="${AWS_DEFAULT_PROFILE}"
    CRED_SOURCE="AWS_DEFAULT_PROFILE=${AWS_DEFAULT_PROFILE}"
  elif [[ -n "${AWS_ACCESS_KEY_ID:-}" ]]; then
    unset AWS_PROFILE 2>/dev/null || true
    CRED_SOURCE="env vars (AWS_ACCESS_KEY_ID)"
  else
    unset AWS_PROFILE 2>/dev/null || true
    CRED_SOURCE="default (~/.aws/credentials or instance role)"
  fi
}

resolve_aws_identity

# ── Resolve paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_HCL="${ROOT_DIR}/backend.hcl"

[[ -f "${BACKEND_HCL}" ]] || error "backend.hcl not found at ${BACKEND_HCL}"

# ── Read backend.hcl values ───────────────────────────────────────────────────
# awk-based parser — works on macOS (BSD) and Linux (GNU) without \s issues
parse_hcl() { awk -F'"' "/^[[:space:]]*$1[[:space:]]*=/ { print \$2; exit }" "${BACKEND_HCL}"; }

STATE_BUCKET=$(parse_hcl "bucket")
STATE_KEY=$(parse_hcl "key")
STATE_REGION=$(parse_hcl "region")
LOCK_TABLE=$(parse_hcl "dynamodb_table")

[[ -n "${STATE_BUCKET}" ]] || error "Could not parse 'bucket' from backend.hcl"
[[ -n "${STATE_REGION}" ]] || error "Could not parse 'region' from backend.hcl"
[[ -n "${LOCK_TABLE}"   ]] || error "Could not parse 'dynamodb_table' from backend.hcl"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         Caltech Prod Stack — Bootstrap & Init                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Credentials  : ${CRED_SOURCE}"
info "State Bucket : ${STATE_BUCKET}"
info "State Key    : ${STATE_KEY}"
info "Lock Table   : ${LOCK_TABLE}"
info "Region       : ${STATE_REGION}"

# ── Prerequisite checks ───────────────────────────────────────────────────────
step "Checking prerequisites"

command -v terraform &>/dev/null \
  || error "terraform not installed — https://developer.hashicorp.com/terraform/downloads"
command -v aws &>/dev/null \
  || error "aws CLI not installed — https://aws.amazon.com/cli/"

TF_VERSION=$(terraform version -json 2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null \
  || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

AWS_CLI_VERSION=$(aws --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

info "Terraform : v${TF_VERSION}"
info "AWS CLI   : v${AWS_CLI_VERSION}"

# ── Verify AWS credentials ────────────────────────────────────────────────────
step "Verifying AWS credentials (${CRED_SOURCE})"

CALLER=$(aws sts get-caller-identity --output json 2>/dev/null) || {
  echo ""
  echo -e "${RED}[ERROR]${NC} AWS authentication failed."
  echo ""
  echo "  Tried credential source: ${CRED_SOURCE}"
  echo ""
  echo "  Fix options:"
  echo "    1. Pass a named profile:  ./scripts/init.sh --profile <profile-name>"
  echo "    2. Set env variable:      AWS_PROFILE=<name> ./scripts/init.sh"
  echo "    3. Export keys directly:  export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..."
  echo "    4. Configure default:     aws configure"
  echo ""
  echo "  Available profiles on this machine:"
  aws configure list-profiles 2>/dev/null | sed 's/^/    - /' || echo "    (none found)"
  echo ""
  exit 1
}

ACCOUNT_ID=$(echo "${CALLER}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Account'])")
CALLER_ARN=$(echo "${CALLER}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'])")

success "Authenticated as : ${CALLER_ARN}"
success "Account ID       : ${ACCOUNT_ID}"

# ── Create S3 state bucket ───────────────────────────────────────────────────
step "S3 state bucket: ${STATE_BUCKET}"

# head-bucket without --region — S3 bucket names are global
# Use && / || to capture exit code without triggering set -e on a 404
BUCKET_CHECK=$(aws s3api head-bucket --bucket "${STATE_BUCKET}" 2>&1) && BUCKET_EXIT=0 || BUCKET_EXIT=$?

handle_create_result() {
  local create_out="$1"
  if echo "${create_out}" | grep -q "BucketAlreadyOwnedByYou"; then
    warn "Bucket '${STATE_BUCKET}' already exists in your account — continuing"
  elif echo "${create_out}" | grep -q "BucketAlreadyExists"; then
    echo ""
    echo -e "${RED}[ERROR]${NC} Bucket name '${STATE_BUCKET}' is already taken by a different AWS account."
    echo ""
    echo "  S3 bucket names are globally unique. You must choose a unique name."
    echo "  Suggested fix — add your account ID to the name:"
    echo ""
    echo "    bucket = \"caltech-terraform-state-${ACCOUNT_ID}\""
    echo ""
    echo "  Update backend.hcl with the new name, then re-run this script."
    echo ""
    exit 1
  else
    error "Failed to create bucket:\n${create_out}"
  fi
}

if [[ ${BUCKET_EXIT} -eq 0 ]]; then
  warn "Bucket '${STATE_BUCKET}' already exists in your account — skipping creation"
else
  # 403 = bucket exists but owned by a different account (head-bucket may also
  # return 404 for cross-account buckets when the owner has Block Public Access
  # enabled — the create step will then surface BucketAlreadyExists instead)
  if echo "${BUCKET_CHECK}" | grep -q "403\|Forbidden"; then
    echo ""
    echo -e "${RED}[ERROR]${NC} Bucket '${STATE_BUCKET}' exists but belongs to another AWS account."
    echo ""
    echo "  Suggested fix — add your account ID to make the name unique:"
    echo "    bucket = \"caltech-terraform-state-${ACCOUNT_ID}\""
    echo ""
    echo "  Update backend.hcl and re-run this script."
    echo ""
    exit 1
  fi

  # Attempt creation
  if [[ "${STATE_REGION}" == "us-east-1" ]]; then
    CREATE_OUT=$(aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${STATE_REGION}" 2>&1) && \
      success "Bucket created: ${STATE_BUCKET}" || handle_create_result "${CREATE_OUT}"
  else
    CREATE_OUT=$(aws s3api create-bucket \
      --bucket "${STATE_BUCKET}" \
      --region "${STATE_REGION}" \
      --create-bucket-configuration LocationConstraint="${STATE_REGION}" 2>&1) && \
      success "Bucket created: ${STATE_BUCKET}" || handle_create_result "${CREATE_OUT}"
  fi
fi

info "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled
success "Versioning enabled"

info "Enabling server-side encryption (AES-256)..."
aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
      "BucketKeyEnabled": true
    }]
  }'
success "Encryption enabled"

info "Blocking public access..."
aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
success "Public access blocked"

info "Setting lifecycle policy (non-current versions expire after 90 days)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${STATE_BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-state-versions",
      "Status": "Enabled",
      "Filter": { "Prefix": "" },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 }
    }]
  }'
success "Lifecycle policy set"

# ── Create DynamoDB lock table ────────────────────────────────────────────────
step "DynamoDB lock table: ${LOCK_TABLE}"

TABLE_STATUS=$(aws dynamodb describe-table \
  --table-name "${LOCK_TABLE}" \
  --region "${STATE_REGION}" \
  --query "Table.TableStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${TABLE_STATUS}" == "ACTIVE" ]]; then
  warn "Table already exists and is ACTIVE — skipping creation"
else
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${STATE_REGION}"

  info "Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists \
    --table-name "${LOCK_TABLE}" \
    --region "${STATE_REGION}"
  success "Table ready: ${LOCK_TABLE}"
fi

info "Enabling Point-in-Time Recovery..."
aws dynamodb update-continuous-backups \
  --table-name "${LOCK_TABLE}" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
  --region "${STATE_REGION}" &>/dev/null \
  && success "PITR enabled" \
  || warn "PITR not enabled (may need extra DynamoDB permissions — non-critical)"

# ── terraform init ────────────────────────────────────────────────────────────
step "terraform init"
cd "${ROOT_DIR}"

terraform init \
  -backend-config=backend.hcl \
  -upgrade \
  -reconfigure

success "terraform init complete"

# ── terraform validate ────────────────────────────────────────────────────────
step "terraform validate"
terraform validate
success "terraform validate passed"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║                  Bootstrap Complete!                        ║${NC}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Credentials : ${CYAN}${CRED_SOURCE}${NC}"
echo -e "  Account ID  : ${CYAN}${ACCOUNT_ID}${NC}"
echo -e "  State file  : ${CYAN}s3://${STATE_BUCKET}/${STATE_KEY}${NC}"
echo -e "  Lock table  : ${CYAN}${LOCK_TABLE} (${STATE_REGION})${NC}"
echo ""
echo -e "${BOLD}Next — deploy one module at a time:${NC}"
echo ""
echo -e "  ${YELLOW}terraform apply -target=module.kms${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.security_groups${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.s3${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.secrets${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.msk${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.iam${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.aurora_source${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.aurora_sink${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.elasticache${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.ec2${NC}"
echo -e "  ${YELLOW}terraform apply -target=module.msk_connect${NC}"
echo -e "  ${YELLOW}terraform apply${NC}   # final pass"
echo ""
