#!/usr/bin/env bash
###############################################################################
# prod-stack/scripts/migrate-to-s3-lock.sh
#
# Migrates an environment from DynamoDB-based state locking to native S3
# locking (use_lockfile=true) WITHOUT moving the state file (Path B).
#
# What it does, in order:
#   1. Pre-flight: terraform >= 1.10, aws CLI, jq present
#   2. Reads envs/<env>.backend.hcl + locally-cached backend config
#   3. Verifies bucket/key in backend.hcl match the live state location
#      (Path B requires state to STAY PUT — only the lock mechanism changes)
#   4. Backs up the state file to ~/tf-state-backups/
#   5. Patches envs/<env>.backend.hcl:
#        + use_lockfile = true
#        - dynamodb_table = "..."
#   6. Wipes local .terraform metadata
#   7. Runs `terraform init -backend-config=envs/<env>.backend.hcl`
#   8. Runs `terraform plan` and asserts "No changes"
#   9. Optionally deletes the old DynamoDB lock table (--delete-ddb-table)
#
# Usage:
#   ./scripts/migrate-to-s3-lock.sh --env poc --profile caltect-account
#   ./scripts/migrate-to-s3-lock.sh --env poc --profile default --dry-run
#   ./scripts/migrate-to-s3-lock.sh --env poc --profile default --auto-approve
#   ./scripts/migrate-to-s3-lock.sh --env poc --delete-ddb-table
#   ./scripts/migrate-to-s3-lock.sh --rollback --env poc
#
# Flags:
#   --env <name>         Environment short name (poc, dev, qas, prod) [required]
#   --profile <name>     AWS profile to use (overrides backend.hcl profile)
#   --backup-dir <path>  Where to store the state backup (default ~/tf-state-backups)
#   --dry-run            Print every action, modify nothing
#   --auto-approve       Skip confirmation prompts
#   --delete-ddb-table   After successful migration, delete the old DynamoDB lock table
#   --rollback           Re-add DynamoDB lock to backend.hcl and re-init (state stays put)
#   --help               Show this help text
###############################################################################

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
fatal()   { err "$@"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ── Defaults ─────────────────────────────────────────────────────────────────
ENV_NAME=""
PROFILE_OVERRIDE=""
BACKUP_DIR="${HOME}/tf-state-backups"
DRY_RUN=false
AUTO_APPROVE=false
DELETE_DDB_TABLE=false
ROLLBACK=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Arg parsing ──────────────────────────────────────────────────────────────
print_help() {
  sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)              ENV_NAME="$2"; shift 2 ;;
    --profile)          PROFILE_OVERRIDE="$2"; shift 2 ;;
    --backup-dir)       BACKUP_DIR="$2"; shift 2 ;;
    --dry-run)          DRY_RUN=true; shift ;;
    --auto-approve|-y)  AUTO_APPROVE=true; shift ;;
    --delete-ddb-table) DELETE_DDB_TABLE=true; shift ;;
    --rollback)         ROLLBACK=true; shift ;;
    --help|-h)          print_help ;;
    *)                  fatal "Unknown argument: $1  (use --help)" ;;
  esac
done

[[ -n "${ENV_NAME}" ]] || fatal "--env is required (poc, dev, qas, prod)"

BACKEND_HCL="${ROOT_DIR}/envs/${ENV_NAME}.backend.hcl"
TFVARS_FILE="${ROOT_DIR}/envs/${ENV_NAME}.tfvars"

[[ -f "${BACKEND_HCL}" ]] || fatal "Backend file not found: ${BACKEND_HCL}"
[[ -f "${TFVARS_FILE}" ]] || fatal "Tfvars file not found: ${TFVARS_FILE}"

# ── Helpers ──────────────────────────────────────────────────────────────────
parse_hcl() {
  # $1 = key name in backend.hcl
  awk -F'"' "/^[[:space:]]*$1[[:space:]]*=/ { print \$2; exit }" "${BACKEND_HCL}"
}

confirm() {
  $AUTO_APPROVE && return 0
  $DRY_RUN && return 0
  read -r -p "$(echo -e "${YELLOW}? $1 [y/N]:${NC} ")" reply
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

run() {
  # Echo + execute (unless dry-run)
  echo -e "${CYAN}\$ $*${NC}"
  $DRY_RUN || eval "$@"
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
if $ROLLBACK; then
  echo -e "${BOLD}║   Caltech Stack — Rollback to DynamoDB Locking (${ENV_NAME})         ║${NC}"
else
  echo -e "${BOLD}║   Caltech Stack — Migrate to S3 Native Locking (${ENV_NAME})         ║${NC}"
fi
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Environment        : ${ENV_NAME}"
info "Backend file       : ${BACKEND_HCL}"
info "Backup directory   : ${BACKUP_DIR}"
info "Dry-run            : ${DRY_RUN}"
info "Auto-approve       : ${AUTO_APPROVE}"
info "Delete DDB table   : ${DELETE_DDB_TABLE}"
info "Mode               : $($ROLLBACK && echo ROLLBACK || echo MIGRATE)"

# ── Step 1 — Pre-flight ──────────────────────────────────────────────────────
step "Step 1 — Pre-flight checks"

command -v terraform >/dev/null 2>&1 || fatal "terraform not installed"
command -v aws       >/dev/null 2>&1 || fatal "aws CLI not installed"

TF_VERSION=$(terraform version -json 2>/dev/null | awk -F'"' '/"terraform_version"/{print $4; exit}')
if [[ -z "${TF_VERSION}" ]]; then
  TF_VERSION=$(terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
fi

# Numeric compare: require >= 1.10
TF_MAJOR=$(echo "${TF_VERSION}" | cut -d. -f1)
TF_MINOR=$(echo "${TF_VERSION}" | cut -d. -f2)
if (( TF_MAJOR < 1 )) || (( TF_MAJOR == 1 && TF_MINOR < 10 )); then
  fatal "Terraform ${TF_VERSION} is too old. Need >= 1.10 for use_lockfile support."
fi
ok "Terraform version: ${TF_VERSION}"

# ── Step 2 — Read target backend.hcl + cached config ─────────────────────────
step "Step 2 — Read backend configurations"

TARGET_BUCKET=$(parse_hcl "bucket")
TARGET_KEY=$(parse_hcl "key")
TARGET_REGION=$(parse_hcl "region")
TARGET_PROFILE=$(parse_hcl "profile")
CURRENT_DDB=$(awk -F'"' '/^[[:space:]]*dynamodb_table[[:space:]]*=/{print $2; exit}' "${BACKEND_HCL}")
CURRENT_USE_LOCKFILE=$(awk '/^[[:space:]]*use_lockfile[[:space:]]*=/{gsub(/[[:space:]]/,""); split($0,a,"="); print a[2]; exit}' "${BACKEND_HCL}")

# Profile override
EFFECTIVE_PROFILE="${PROFILE_OVERRIDE:-${TARGET_PROFILE}}"
[[ -n "${EFFECTIVE_PROFILE}" ]] || fatal "No AWS profile specified (neither --profile flag nor backend.hcl)"

info "Target bucket          : ${TARGET_BUCKET}"
info "Target key             : ${TARGET_KEY}"
info "Target region          : ${TARGET_REGION}"
info "Effective AWS profile  : ${EFFECTIVE_PROFILE}"
info "Current dynamodb_table : ${CURRENT_DDB:-<none>}"
info "Current use_lockfile   : ${CURRENT_USE_LOCKFILE:-<unset>}"

# Read the locally-cached backend (.terraform/terraform.tfstate) if present
CACHED_BUCKET=""
CACHED_KEY=""
CACHED_DDB=""
if [[ -f "${ROOT_DIR}/.terraform/terraform.tfstate" ]]; then
  if command -v jq >/dev/null 2>&1; then
    CACHED_BUCKET=$(jq -r '.backend.config.bucket // empty'         "${ROOT_DIR}/.terraform/terraform.tfstate")
    CACHED_KEY=$(jq -r    '.backend.config.key // empty'            "${ROOT_DIR}/.terraform/terraform.tfstate")
    CACHED_DDB=$(jq -r    '.backend.config.dynamodb_table // empty' "${ROOT_DIR}/.terraform/terraform.tfstate")
  fi
fi

if [[ -n "${CACHED_BUCKET}" ]]; then
  info "Cached backend bucket  : ${CACHED_BUCKET}"
  info "Cached backend key     : ${CACHED_KEY}"
  info "Cached backend DDB     : ${CACHED_DDB:-<none>}"

  if [[ "${CACHED_BUCKET}" != "${TARGET_BUCKET}" ]] || [[ "${CACHED_KEY}" != "${TARGET_KEY}" ]]; then
    warn "Cached backend points at a DIFFERENT bucket/key than ${BACKEND_HCL}"
    warn "Path B requires state to STAY PUT — only the lock mechanism may change."
    warn "If the live state is at:"
    warn "    s3://${CACHED_BUCKET}/${CACHED_KEY}"
    warn "...then ${BACKEND_HCL} must be edited to match BEFORE running this script,"
    warn "OR pass the correct backend file. Aborting to prevent data loss."
    fatal "Backend bucket/key mismatch. Reconcile and re-run."
  fi
fi

# ── Step 3 — Verify AWS access + state file exists ───────────────────────────
step "Step 3 — Verify AWS access and live state file"

CALLER=$(aws sts get-caller-identity --profile "${EFFECTIVE_PROFILE}" --output json 2>&1) \
  || fatal "AWS authentication failed for profile '${EFFECTIVE_PROFILE}'"

ACCOUNT_ID=$(echo "${CALLER}" | awk -F'"' '/"Account"/{print $4; exit}')
ARN=$(echo "${CALLER}"        | awk -F'"' '/"Arn"/{print $4; exit}')
ok "Authenticated as : ${ARN}"
ok "Account ID       : ${ACCOUNT_ID}"

# Confirm state object exists
STATE_URI="s3://${TARGET_BUCKET}/${TARGET_KEY}"
if ! aws s3 ls "${STATE_URI}" --profile "${EFFECTIVE_PROFILE}" >/dev/null 2>&1; then
  fatal "Cannot read state file at ${STATE_URI} (check bucket/key/profile permissions)"
fi
STATE_SIZE=$(aws s3 ls "${STATE_URI}" --profile "${EFFECTIVE_PROFILE}" | awk '{print $3}')
ok "State file found : ${STATE_URI} (${STATE_SIZE} bytes)"
[[ "${STATE_SIZE}" -gt 0 ]] || fatal "State file is empty — refusing to migrate."

# ── Step 4 — Back up state out-of-band ───────────────────────────────────────
step "Step 4 — Backup state to ${BACKUP_DIR}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${ENV_NAME}-state-${TIMESTAMP}.tfstate"

run "mkdir -p '${BACKUP_DIR}'"
run "aws s3 cp '${STATE_URI}' '${BACKUP_FILE}' --profile '${EFFECTIVE_PROFILE}'"

if ! $DRY_RUN; then
  [[ -s "${BACKUP_FILE}" ]] || fatal "Backup file is empty: ${BACKUP_FILE}"
  ok "Backup saved : ${BACKUP_FILE}"
fi

# ── Step 5 — Confirm before mutating anything ────────────────────────────────
step "Step 5 — Confirm migration plan"

if $ROLLBACK; then
  echo "  • Re-add  dynamodb_table = \"caltech-terraform-lock\""
  echo "  • Remove  use_lockfile   = true"
  echo "  • Wipe local .terraform metadata"
  echo "  • terraform init -backend-config=${BACKEND_HCL}"
  echo "  • terraform plan -var-file=envs/${ENV_NAME}.tfvars  (must show 'No changes')"
else
  echo "  • Add     use_lockfile   = true       (if not already set)"
  echo "  • Remove  dynamodb_table = \"${CURRENT_DDB:-<none>}\"  (if set)"
  echo "  • Wipe local .terraform metadata"
  echo "  • terraform init -backend-config=${BACKEND_HCL}"
  echo "  • terraform plan -var-file=envs/${ENV_NAME}.tfvars  (must show 'No changes')"
  if $DELETE_DDB_TABLE && [[ -n "${CURRENT_DDB}" ]]; then
    echo "  • Delete DynamoDB table : ${CURRENT_DDB} (region ${TARGET_REGION})"
  fi
fi
echo ""

if ! confirm "Proceed with migration?"; then
  warn "Aborted by user."
  exit 0
fi

# ── Step 6 — Patch backend.hcl ───────────────────────────────────────────────
step "Step 6 — Patch ${BACKEND_HCL}"

if $ROLLBACK; then
  # Add dynamodb_table, remove use_lockfile
  if [[ -z "${CACHED_DDB}" ]] && [[ -z "${CURRENT_DDB}" ]]; then
    warn "No DynamoDB table name known. Defaulting to 'caltech-terraform-lock'."
    DDB_RESTORE="caltech-terraform-lock"
  else
    DDB_RESTORE="${CACHED_DDB:-${CURRENT_DDB:-caltech-terraform-lock}}"
  fi

  if [[ "${CURRENT_USE_LOCKFILE}" == "true" ]]; then
    run "sed -i.bak '/^[[:space:]]*use_lockfile[[:space:]]*=/d' '${BACKEND_HCL}'"
  fi
  if [[ -z "${CURRENT_DDB}" ]]; then
    run "printf '\\ndynamodb_table = \"%s\"\\n' '${DDB_RESTORE}' >> '${BACKEND_HCL}'"
  fi
  ok "Rolled back to DynamoDB locking (table: ${DDB_RESTORE})"
else
  # Add use_lockfile = true, remove dynamodb_table line
  if [[ -n "${CURRENT_DDB}" ]]; then
    run "sed -i.bak '/^[[:space:]]*dynamodb_table[[:space:]]*=/d' '${BACKEND_HCL}'"
    ok "Removed dynamodb_table from ${BACKEND_HCL}"
  else
    info "dynamodb_table already absent — no change."
  fi
  if [[ "${CURRENT_USE_LOCKFILE}" != "true" ]]; then
    run "printf '\\nuse_lockfile = true\\n' >> '${BACKEND_HCL}'"
    ok "Added use_lockfile = true to ${BACKEND_HCL}"
  else
    info "use_lockfile = true already present — no change."
  fi
fi

if ! $DRY_RUN; then
  echo ""
  info "Updated backend.hcl contents:"
  echo "─────────────────────────────────────────────"
  cat "${BACKEND_HCL}" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' || true
  echo "─────────────────────────────────────────────"
fi

# ── Step 7 — Wipe local terraform metadata and re-init ───────────────────────
step "Step 7 — Re-initialize Terraform"

run "rm -rf '${ROOT_DIR}/.terraform' '${ROOT_DIR}/.terraform.lock.hcl'"
run "cd '${ROOT_DIR}' && terraform init -backend-config='${BACKEND_HCL}' -input=false"

# ── Step 8 — Verify no drift ─────────────────────────────────────────────────
step "Step 8 — terraform plan (must show 'No changes')"

PLAN_TMP=$(mktemp)
if $DRY_RUN; then
  warn "Skipping plan in dry-run mode."
else
  set +e
  cd "${ROOT_DIR}"
  terraform plan -var-file="envs/${ENV_NAME}.tfvars" -detailed-exitcode -input=false -no-color > "${PLAN_TMP}" 2>&1
  PLAN_EXIT=$?
  set -e

  case "${PLAN_EXIT}" in
    0)
      ok "Plan clean — No changes. Migration successful."
      ;;
    2)
      err "Plan shows DRIFT after migration. This is UNEXPECTED for Path B."
      err "First 50 lines of plan output:"
      head -50 "${PLAN_TMP}" | sed 's/^/    /'
      err ""
      err "Your state file is still safe at ${STATE_URI}"
      err "Backup is at ${BACKUP_FILE}"
      err "To roll back this script's changes:"
      err "    $0 --env ${ENV_NAME} --profile ${EFFECTIVE_PROFILE} --rollback"
      rm -f "${PLAN_TMP}"
      exit 2
      ;;
    *)
      err "terraform plan failed (exit ${PLAN_EXIT})."
      cat "${PLAN_TMP}" | sed 's/^/    /'
      rm -f "${PLAN_TMP}"
      exit "${PLAN_EXIT}"
      ;;
  esac
  rm -f "${PLAN_TMP}"
fi

# ── Step 9 — Optional: delete the old DynamoDB lock table ────────────────────
if $DELETE_DDB_TABLE && [[ -n "${CURRENT_DDB}" ]] && ! $ROLLBACK; then
  step "Step 9 — Delete DynamoDB lock table"

  if confirm "Really delete DynamoDB table '${CURRENT_DDB}' in ${TARGET_REGION}?"; then
    run "aws dynamodb delete-table --table-name '${CURRENT_DDB}' --region '${TARGET_REGION}' --profile '${EFFECTIVE_PROFILE}'"
    ok "DynamoDB table deleted: ${CURRENT_DDB}"
  else
    warn "DynamoDB deletion skipped. Run with --delete-ddb-table later to clean it up."
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
if $ROLLBACK; then
  echo -e "${BOLD}${GREEN}║                  Rollback Complete                            ║${NC}"
else
  echo -e "${BOLD}${GREEN}║                  Migration Complete                           ║${NC}"
fi
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Environment   : ${CYAN}${ENV_NAME}${NC}"
echo -e "  State URI     : ${CYAN}${STATE_URI}${NC}"
echo -e "  Lock method   : $($ROLLBACK && echo "${CYAN}DynamoDB${NC}" || echo "${CYAN}S3 native (use_lockfile)${NC}")"
echo -e "  Backup file   : ${CYAN}${BACKUP_FILE}${NC}"
echo ""

if ! $ROLLBACK; then
  echo -e "${BOLD}Verify the lock works (optional smoke test):${NC}"
  echo -e "  ${YELLOW}terraform apply -var-file=envs/${ENV_NAME}.tfvars${NC}"
  echo -e "  ${YELLOW}# Wait at the 'Do you want to perform these actions?' prompt${NC}"
  echo -e "  ${YELLOW}# In another terminal:${NC}"
  echo -e "  ${YELLOW}aws s3 ls s3://${TARGET_BUCKET}/$(dirname "${TARGET_KEY}")/ --profile ${EFFECTIVE_PROFILE}${NC}"
  echo -e "  ${YELLOW}# You should see terraform.tfstate.tflock alongside terraform.tfstate${NC}"
  echo -e "  ${YELLOW}# Then type 'no' to cancel the apply${NC}"
  echo ""
fi

echo -e "${BOLD}To roll back this change:${NC}"
echo -e "  ${YELLOW}$0 --env ${ENV_NAME} --profile ${EFFECTIVE_PROFILE} --rollback${NC}"
echo ""
