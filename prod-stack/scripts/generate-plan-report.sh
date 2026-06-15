#!/usr/bin/env bash
###############################################################################
# prod-stack/scripts/generate-plan-report.sh
#
# Runs `terraform plan` for the chosen environment and bundles the output into
# a client-ready report folder containing:
#   • <env>-plan.tfplan         binary plan (for internal apply)
#   • <env>-plan.txt            full human-readable plan
#   • <env>-plan.json           structured JSON (for tooling)
#   • <env>-summary.md          curated summary for the client
#   • <env>-resource-list.csv   flat list of all resources to be created
#
# Usage:
#   ./scripts/generate-plan-report.sh --env dev --profile default
#   ./scripts/generate-plan-report.sh --env poc --profile default
#   ./scripts/generate-plan-report.sh --env dev --profile default --out ~/Desktop/caltech-dev-plan
###############################################################################

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fatal() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# ── Defaults ─────────────────────────────────────────────────────────────────
ENV_NAME=""
PROFILE=""
OUT_DIR=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Args ─────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)     ENV_NAME="$2"; shift 2 ;;
    --profile) PROFILE="$2";  shift 2 ;;
    --out)     OUT_DIR="$2";  shift 2 ;;
    --help|-h)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) fatal "Unknown arg: $1  (use --help)" ;;
  esac
done

[[ -n "${ENV_NAME}" ]] || fatal "--env is required (poc|dev|qas|prod)"

BACKEND_HCL="${ROOT_DIR}/envs/${ENV_NAME}.backend.hcl"
TFVARS_FILE="${ROOT_DIR}/envs/${ENV_NAME}.tfvars"
[[ -f "${BACKEND_HCL}" ]] || fatal "Backend file not found: ${BACKEND_HCL}"
[[ -f "${TFVARS_FILE}" ]] || fatal "tfvars file not found: ${TFVARS_FILE}"

# Default profile from backend.hcl if not given
if [[ -z "${PROFILE}" ]]; then
  PROFILE=$(awk -F'"' '/^[[:space:]]*profile[[:space:]]*=/{print $2; exit}' "${BACKEND_HCL}")
fi
[[ -n "${PROFILE}" ]] || fatal "No AWS profile (--profile not given, none in backend.hcl)"

# Read tfvars values for the summary
TFV_REGION=$(awk -F'"' '/^aws_region[[:space:]]*=/{print $2; exit}' "${TFVARS_FILE}")
TFV_PROJECT=$(awk -F'"' '/^project[[:space:]]*=/{print $2; exit}' "${TFVARS_FILE}")
TFV_ENV=$(awk -F'"' '/^environment[[:space:]]*=/{print $2; exit}' "${TFVARS_FILE}")
TFV_VPC_CIDR=$(awk -F'"' '/^vpc_cidr[[:space:]]*=/{print $2; exit}' "${TFVARS_FILE}")
TFV_CREATE_VPC=$(awk '/^create_vpc[[:space:]]*=/{gsub(/[[:space:]]/,""); split($0,a,"="); print a[2]; exit}' "${TFVARS_FILE}")
TFV_PRIVATE_EC2=$(awk '/^ec2_in_private_subnet[[:space:]]*=/{gsub(/[[:space:]]/,""); split($0,a,"="); print a[2]; exit}' "${TFVARS_FILE}")

# Output dir default
if [[ -z "${OUT_DIR}" ]]; then
  OUT_DIR="${ROOT_DIR}/plan-reports/${ENV_NAME}-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "${OUT_DIR}"

# Banner
echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       Caltech Stack — Plan Report Generator                  ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Environment   : ${ENV_NAME}"
info "AWS Profile   : ${PROFILE}"
info "AWS Region    : ${TFV_REGION}"
info "VPC CIDR      : ${TFV_VPC_CIDR} (create_vpc=${TFV_CREATE_VPC})"
info "EC2 placement : $([[ "${TFV_PRIVATE_EC2}" == "true" ]] && echo "PRIVATE subnets" || echo "PUBLIC subnets (legacy)")"
info "Output dir    : ${OUT_DIR}"

# ── Step 1 — Init + plan ─────────────────────────────────────────────────────
step "Step 1 — Initialize backend + run terraform plan"

cd "${ROOT_DIR}"

# Wipe local state cache to avoid hitting a stale backend
rm -rf .terraform .terraform.lock.hcl

terraform init -backend-config="${BACKEND_HCL}" -input=false -no-color >/dev/null 2>&1 \
  || fatal "terraform init failed — re-run manually with: terraform init -backend-config=${BACKEND_HCL}"
ok "Backend initialized: $(awk -F'"' '/^key/{print $2; exit}' "${BACKEND_HCL}")"

PLAN_BIN="${OUT_DIR}/${ENV_NAME}-plan.tfplan"
PLAN_TXT="${OUT_DIR}/${ENV_NAME}-plan.txt"
PLAN_JSON="${OUT_DIR}/${ENV_NAME}-plan.json"

info "Generating plan (this may take a minute)..."
set +e
terraform plan \
  -var-file="${TFVARS_FILE}" \
  -out="${PLAN_BIN}" \
  -detailed-exitcode \
  -input=false \
  -no-color > "${PLAN_TXT}" 2>&1
PLAN_EXIT=$?
set -e

case "${PLAN_EXIT}" in
  0) PLAN_VERDICT="No changes — infrastructure matches configuration." ;;
  2) PLAN_VERDICT="Changes detected — see plan output for details." ;;
  *) cat "${PLAN_TXT}" | tail -40 | sed 's/^/    /'
     fatal "terraform plan failed (exit ${PLAN_EXIT})" ;;
esac
ok "Plan saved : ${PLAN_BIN}"
ok "Plan text  : ${PLAN_TXT}"
ok "Verdict    : ${PLAN_VERDICT}"

# ── Step 2 — JSON form ───────────────────────────────────────────────────────
step "Step 2 — Export plan as JSON"

terraform show -json "${PLAN_BIN}" > "${PLAN_JSON}" 2>/dev/null \
  || warn "terraform show -json failed (continuing)"
[[ -s "${PLAN_JSON}" ]] && ok "JSON plan : ${PLAN_JSON} ($(wc -c < "${PLAN_JSON}") bytes)"

# ── Step 3 — Resource counts ─────────────────────────────────────────────────
step "Step 3 — Compute resource counts"

if command -v jq >/dev/null 2>&1 && [[ -s "${PLAN_JSON}" ]]; then
  CREATE_COUNT=$(jq '[.resource_changes[]? | select(.change.actions==["create"])] | length' "${PLAN_JSON}")
  UPDATE_COUNT=$(jq '[.resource_changes[]? | select(.change.actions==["update"])] | length' "${PLAN_JSON}")
  DESTROY_COUNT=$(jq '[.resource_changes[]? | select(.change.actions==["delete"])] | length' "${PLAN_JSON}")
  REPLACE_COUNT=$(jq '[.resource_changes[]? | select(.change.actions==["delete","create"] or .change.actions==["create","delete"])] | length' "${PLAN_JSON}")
else
  # Fallback if jq absent
  CREATE_COUNT=$(grep -c "will be created" "${PLAN_TXT}" || echo 0)
  UPDATE_COUNT=$(grep -c "will be updated in-place" "${PLAN_TXT}" || echo 0)
  DESTROY_COUNT=$(grep -c "will be destroyed" "${PLAN_TXT}" || echo 0)
  REPLACE_COUNT=$(grep -c "must be replaced" "${PLAN_TXT}" || echo 0)
fi

info "Resources to add     : ${CREATE_COUNT}"
info "Resources to update  : ${UPDATE_COUNT}"
info "Resources to destroy : ${DESTROY_COUNT}"
info "Resources to replace : ${REPLACE_COUNT}"

# ── Step 4 — Per-module breakdown CSV ────────────────────────────────────────
step "Step 4 — Per-module resource list"

RES_CSV="${OUT_DIR}/${ENV_NAME}-resource-list.csv"
{
  echo "action,module,resource_type,resource_name,full_address"
  if command -v jq >/dev/null 2>&1 && [[ -s "${PLAN_JSON}" ]]; then
    jq -r '.resource_changes[]?
      | [
          (.change.actions|join("|")),
          (.module_address // "(root)"),
          .type,
          .name,
          .address
        ] | @csv' "${PLAN_JSON}"
  fi
} > "${RES_CSV}"

if [[ "$(wc -l < "${RES_CSV}")" -gt 1 ]]; then
  ok "Resource list CSV : ${RES_CSV} ($(($(wc -l < "${RES_CSV}") - 1)) rows)"
fi

# Compute per-module summary for the markdown report
MODULE_SUMMARY=""
if command -v jq >/dev/null 2>&1 && [[ -s "${PLAN_JSON}" ]]; then
  MODULE_SUMMARY=$(jq -r '
    [.resource_changes[]?
      | select(.change.actions==["create"])
      | (.module_address // "(root)")
    ]
    | group_by(.)
    | map({module: .[0], count: length})
    | sort_by(-.count)
    | .[]
    | "| \(.module) | \(.count) |"
  ' "${PLAN_JSON}")
fi

# ── Step 5 — Generate client-friendly summary ────────────────────────────────
step "Step 5 — Generate client summary"

SUMMARY_MD="${OUT_DIR}/${ENV_NAME}-summary.md"

cat > "${SUMMARY_MD}" <<EOF
# Caltech ${ENV_NAME^^} — Terraform Plan Report

> Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
> Generated by: $(whoami)@$(hostname)
> Verdict: **${PLAN_VERDICT}**

---

## Deployment Target

| | |
|---|---|
| AWS account | $(aws sts get-caller-identity --profile "${PROFILE}" --query Account --output text 2>/dev/null || echo "(see report bundle)") |
| AWS region | \`${TFV_REGION}\` |
| AWS profile | \`${PROFILE}\` |
| Project | \`${TFV_PROJECT}\` |
| Environment | \`${TFV_ENV}\` |
| State location | \`s3://$(awk -F'"' '/^bucket/{print $2; exit}' "${BACKEND_HCL}")/$(awk -F'"' '/^key/{print $2; exit}' "${BACKEND_HCL}")\` |

## Plan Summary

| Action | Count |
|---|---|
| Resources to **create** | **${CREATE_COUNT}** |
| Resources to update in-place | ${UPDATE_COUNT} |
| Resources to destroy | ${DESTROY_COUNT} |
| Resources to replace | ${REPLACE_COUNT} |

## Network Topology

- **VPC**: ${TFV_VPC_CIDR}  (mode: $([[ "${TFV_CREATE_VPC}" == "true" ]] && echo "Terraform creates fresh VPC" || echo "uses existing VPC"))
- **EC2 placement**: $([[ "${TFV_PRIVATE_EC2}" == "true" ]] && echo "**PRIVATE subnets** — no public IPs, SSM access only, outbound via NAT" || echo "Public subnets (legacy POC layout)")
- **Inbound admin access**: AWS Systems Manager Session Manager only (no SSH from internet)
- **Outbound internet**: $([[ "${TFV_PRIVATE_EC2}" == "true" ]] && echo "NAT Gateway (single, in public subnet)" || echo "Direct via Internet Gateway")
- **S3 access**: VPC Gateway endpoint (private)

## Resources by Module
EOF

if [[ -n "${MODULE_SUMMARY}" ]]; then
  cat >> "${SUMMARY_MD}" <<EOF

| Module | Resources to create |
|---|---|
${MODULE_SUMMARY}
EOF
else
  echo "" >> "${SUMMARY_MD}"
  echo "_(See \`${ENV_NAME}-resource-list.csv\` for the full list — \`jq\` not available to compute breakdown automatically.)_" >> "${SUMMARY_MD}"
fi

cat >> "${SUMMARY_MD}" <<EOF

## What this stack delivers

A production-grade Change Data Capture (CDC) pipeline on AWS:

\`\`\`
EC2 App Server (Txn Simulator)
       │
       ▼
Aurora PostgreSQL Source DB (Serverless v2)
       │  (logical replication)
       ▼
MSK Connect + Debezium (5 connectors, one per table)
       │
       ▼
Amazon MSK (Kafka, 3 brokers, kafka.m5.2xlarge)
       │
       ▼
Downstream consumers:
  • ElastiCache for Redis (Serverless)
  • Aurora PostgreSQL Sink (Serverless v2)
\`\`\`

## Security Posture

- All 5 KMS customer-managed keys (per service: S3 / Secrets / Aurora / Redis / EBS)
- All EBS volumes encrypted with customer-managed CMK
- All RDS clusters encrypted at rest and in transit (\`rds.force_ssl=1\`)
- MSK encryption: SSE-KMS at rest, TLS in transit (broker↔client + in-cluster)
- All Secrets Manager secrets encrypted with customer-managed KMS key
- S3 buckets: SSE-S3, public access blocked, versioning enabled
- IAM: least-privilege roles (EC2 instance profile, MSK Connect role)
- No public IPs on EC2 (when \`ec2_in_private_subnet = true\`)
- Admin access: AWS Systems Manager Session Manager only

## Cost Estimate (us-${TFV_REGION#us-} approx, on-demand)

| Component | Approx monthly |
|---|---|
| MSK Provisioned (3 × kafka.m5.2xlarge + 3 TB EBS) | ~\$1,395 |
| MSK Connect (5 connectors, 2–4 workers each) | ~\$800–1,600 |
| EC2 (1 × m6i.2xlarge + 2 × t3.xlarge) | ~\$525 |
| Aurora Source + Sink (Serverless v2, 0.5–16 ACU each) | ~\$90–500 |
| ElastiCache Serverless (Redis) | ~\$80 |
| NAT Gateway + data transfer | ~\$70 |
| S3, KMS, Secrets, CloudWatch | ~\$50 |
| **Total (rough)** | **~\$3,000–4,200 / month** |

> Final cost depends on actual CDC throughput. MSK + MSK Connect are the largest fixed-cost items.

## Files in this Report Bundle

| File | Purpose |
|---|---|
| \`${ENV_NAME}-summary.md\` | This document (high-level overview for stakeholders) |
| \`${ENV_NAME}-plan.txt\` | Full human-readable Terraform plan output |
| \`${ENV_NAME}-plan.tfplan\` | Binary plan file (used internally for \`terraform apply\`) |
| \`${ENV_NAME}-plan.json\` | Structured JSON of the plan (for tooling / automated review) |
| \`${ENV_NAME}-resource-list.csv\` | Flat CSV of every resource action |

## Next Steps

1. Review the resource list (\`${ENV_NAME}-resource-list.csv\`) and the full plan (\`${ENV_NAME}-plan.txt\`).
2. Confirm the region, VPC CIDR, and sizing are correct for your environment.
3. Approve the plan, then run:

   \`\`\`bash
   cd prod-stack
   terraform init -backend-config=envs/${ENV_NAME}.backend.hcl
   terraform apply ${ENV_NAME}-plan.tfplan
   \`\`\`

4. Total deployment time: **~1.5 to 2 hours** (MSK is the long pole at 30–40 minutes).

---

_Generated automatically by \`scripts/generate-plan-report.sh\`_
EOF

ok "Client summary : ${SUMMARY_MD}"

# ── Step 6 — Zip the bundle ──────────────────────────────────────────────────
step "Step 6 — Bundle as ZIP (for emailing)"

ZIP_FILE="${OUT_DIR}.zip"
if command -v zip >/dev/null 2>&1; then
  (cd "$(dirname "${OUT_DIR}")" && zip -qr "$(basename "${ZIP_FILE}")" "$(basename "${OUT_DIR}")")
  ok "ZIP bundle : ${ZIP_FILE} ($(du -h "${ZIP_FILE}" | awk '{print $1}'))"
else
  warn "'zip' not installed — skipped. Send the folder ${OUT_DIR} instead."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║              Plan Report Generated                            ║${NC}"
echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Verdict     : ${CYAN}${PLAN_VERDICT}${NC}"
echo -e "  Adds        : ${CYAN}${CREATE_COUNT}${NC} resources"
echo -e "  Changes     : ${CYAN}${UPDATE_COUNT}${NC} resources"
echo -e "  Destroys    : ${CYAN}${DESTROY_COUNT}${NC} resources"
echo -e "  Bundle dir  : ${CYAN}${OUT_DIR}${NC}"
[[ -f "${ZIP_FILE}" ]] && echo -e "  ZIP for client : ${CYAN}${ZIP_FILE}${NC}"
echo ""
echo -e "${BOLD}Recommended client deliverables:${NC}"
echo -e "  1. ${YELLOW}${ENV_NAME}-summary.md${NC}        ← share this first"
echo -e "  2. ${YELLOW}${ENV_NAME}-plan.txt${NC}          ← attach for technical review"
echo -e "  3. ${YELLOW}${ENV_NAME}-resource-list.csv${NC} ← attach for inventory review"
echo ""
