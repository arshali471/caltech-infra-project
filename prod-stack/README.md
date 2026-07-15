# Caltech AWS Infrastructure — Terraform Deployment Guide

> A production-grade Change Data Capture (CDC) pipeline on AWS — PostgreSQL → Debezium → Kafka (MSK) → PostgreSQL Sink + Redis Cache. Deployed and managed entirely through Terraform with a 4-environment promotion path.

**AWS Account:** `342448511503` · **Profile:** `default` · **State storage:** S3 (no DynamoDB — native S3 locking)

---

## Table of Contents

1. [What gets deployed](#what-gets-deployed)
2. [Environment matrix](#environment-matrix)
3. [Network access modes (public vs private subnet)](#network-access-modes-public-vs-private-subnet)
4. [Prerequisites](#prerequisites)
5. [Quick start (any environment)](#quick-start-any-environment)
6. [Planning a dev deployment (step by step)](#planning-a-dev-deployment-step-by-step)
7. [Architecture](#architecture)
8. [Detailed deployment — phase by phase](#detailed-deployment--phase-by-phase)
9. [Operations](#operations)
10. [Adding a new environment (QAS / PROD)](#adding-a-new-environment-qas--prod)
11. [Destroying an environment](#destroying-an-environment)
12. [Troubleshooting](#troubleshooting)
13. [Related documentation](#related-documentation)

---

## What gets deployed 

| Service | Notes |
|---|---|
| **VPC + Subnets** | Optional — built fresh by `module.vpc` when `create_vpc = true`, or reuses an existing VPC when `false` |
| **EC2 app servers** (×3) | `app-server` (transaction simulator) + `pg-sink-app-server` + `redis-sink-app-server`. No public IPs — SSM Session Manager access only. Subnet tier controlled by `ec2_in_private_subnet` (public for legacy POC, private for DEV/QAS/PROD) |
| **Aurora PostgreSQL Source** | Serverless v2 with logical replication enabled — feeds Debezium |
| **Aurora PostgreSQL Sink** | Serverless v2 — kept as a target DB for downstream consumers |
| **MSK Provisioned** | Apache Kafka 3.9.x, multi-broker across AZs |
| **MSK Connect** | 5 Debezium source connectors (one per table) — fully isolated replication slots |
| **ElastiCache Redis** | Serverless cache, TLS always-on |
| **Supporting** | KMS (5 service-scoped keys), Security Groups (least-privilege), VPC endpoints (SSM + S3), S3 (3 buckets), Secrets Manager, IAM roles |

---

## Environment matrix

The same codebase deploys through **4 environments** in order: **POC → DEV → QAS → PROD**. Each environment is fully isolated — separate state file in S3, separate AWS resources, separate variables.

> **DEV mirrors POC.** Sizing, node counts, ACU limits, retention windows and protection flags are identical to POC. The only differences are region (us-east-2), a fresh VPC, EC2 placed in **private** subnets (per MoM), and dev-specific naming (AMI / key pair / topic prefix / plugin names).

| | **POC** ✅ active | **DEV** 🟡 ready | **QAS** 🔲 future | **PROD** 🔲 future |
|---|---|---|---|---|
| **Region** | `us-west-2` | `us-east-2` | TBD | TBD |
| **Backend config** | `envs/poc.backend.hcl` | `envs/dev.backend.hcl` | `envs/qas.backend.hcl` | `envs/prod.backend.hcl` |
| **Variable file** | `envs/poc.tfvars` | `envs/dev.tfvars` | `envs/qas.tfvars` | `envs/prod.tfvars` |
| **State key in S3** | `caltech/poc/terraform.tfstate` | `caltech/dev/terraform.tfstate` | `caltech/qas/...` | `caltech/prod/...` |
| **Resource prefix** | `caltech-poc-*` | `caltech-dev-*` | `caltech-qas-*` | `caltech-prod-*` |
| **VPC** | Existing (`vpc-0ed44b92f11b73815`) | Created by Terraform (`10.146.0.0/16`) | TBD | TBD |
| **EC2 placement** | Public subnet (legacy) | **Private subnet** (`ec2_in_private_subnet = true`) | Private subnet | Private subnet |
| **Inbound admin access** | SSM Session Manager | SSM Session Manager (VPC endpoints) | SSM | SSM |
| **Outbound internet** | Direct via IGW | NAT Gateway only | NAT Gateway | NAT Gateway |
| **EC2 — app server** | `m6i.2xlarge` (8 vCPU, 32 GiB) | `m6i.2xlarge` *(same as POC)* | TBD | TBD |
| **EC2 — sink servers** | `t3.xlarge` (×2) | `t3.xlarge` (×2) *(same as POC)* | TBD | TBD |
| **EC2 root volume** | 100 GB gp3 | 100 GB gp3 *(same as POC)* | TBD | TBD |
| **MSK brokers** | 3 × `kafka.m5.2xlarge` (1 TB EBS each) | 3 × `kafka.m5.2xlarge` (1 TB EBS each) *(same as POC)* | TBD | TBD |
| **MSK Connect workers** | 2 → 4 (auto-scaling) | 2 → 4 (auto-scaling) *(same as POC)* | TBD | TBD |
| **Aurora min/max ACU** | 0.5 / 16 | 0.5 / 16 *(same as POC)* | TBD | TBD |
| **Redis storage / ECPU** | 1–100 GB / 1k–500k | 1–100 GB / 1k–500k *(same as POC)* | TBD | TBD |
| **Backup retention** | 7 days | 7 days *(same as POC)* | TBD | 7–30 days |
| **Deletion protection** | ✅ enabled | ✅ enabled | ✅ enabled | ✅ enabled |

> **Promotion path:** validate in POC → deploy to DEV → after dev sign-off, copy `dev.tfvars` → `qas.tfvars` with adjustments → after QAS sign-off, copy `qas.*` → `prod.*` and enable deletion protection.

---

## Network access modes (public vs private subnet)

The variable **`ec2_in_private_subnet`** controls where the three EC2 instances (`app-server`, `pg_sink-app-server`, `redis_sink-app-server`) are placed.

| `ec2_in_private_subnet` | EC2 location | Inbound | Outbound | Used by |
|---|---|---|---|---|
| `false` *(default)* | Public subnet, no public IP | SSM Session Manager | Direct via IGW | POC (legacy) |
| `true` | **Private subnet** | SSM Session Manager via interface endpoints | NAT Gateway only | **DEV / QAS / PROD** (per MoM) |

### How private mode works (DEV and onwards)

Per the meeting MoM ("No public subnets for core services"):

```
Internet
   │
   │ inbound  → blocked at NACL/SG; admins use SSM Session Manager only
   │ outbound → routed through NAT Gateway (in public subnet)
   ▼
┌──────────────────────────────────────────────────────────────┐
│ VPC 10.146.0.0/16 (us-east-2)                                │
│                                                              │
│  PUBLIC subnets   only NAT Gateway lives here                │
│                   (+ future ALB / API Gateway if exposed)    │
│                                                              │
│  PRIVATE subnets  EC2 app server                             │
│                   EC2 pg_sink + redis_sink                   │
│                   Aurora Source / Sink                       │
│                   MSK brokers                                │
│                   MSK Connect workers                        │
│                   ElastiCache Redis                          │
│                                                              │
│  VPC Endpoints in private subnets (no internet hop):         │
│    • ssm / ssmmessages / ec2messages  (Session Manager)      │
│    • S3 Gateway endpoint (attached to private route table)   │
└──────────────────────────────────────────────────────────────┘
```

**Result:**
- No EC2 instance has a public IP.
- Admin login uses `aws ssm start-session` (no SSH key, no bastion).
- Yum / pip / GitHub traffic exits via the NAT Gateway.
- S3 traffic stays inside the VPC via the gateway endpoint.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Terraform** | ≥ **1.10** (required for native S3 state locking via `use_lockfile`) |
| **AWS CLI** | ≥ 2.x |
| **AWS Provider** | ≥ 5.95 (set in `versions.tf`) |
| **AWS Profile** | Configured in `~/.aws/credentials` (default profile name: `default`) |
| **IAM permissions** | Admin in the target account, OR scoped: VPC, EC2, EKS, RDS, ElastiCache, MSK, KMS, SecretsManager, IAM, S3, CloudWatch |
| **Plugin ZIPs** *(for MSK Connect)* | Debezium PostgreSQL connector + Confluent JDBC Sink connector — uploaded to S3 before deploying MSK Connect modules |

**Verify locally:**
```bash
terraform version       # >= 1.10.0
aws --version           # >= 2.x
aws sts get-caller-identity --profile default   # confirm correct account
```

---

## Quick start (any environment)

Three commands. The `--env` flag picks the environment — everything else is automatic.

```bash
cd prod-stack
chmod +x scripts/init.sh

# 1. Initialize the chosen environment (creates state bucket, runs terraform init)
./scripts/init.sh --env <poc|dev|qas|prod> --profile default

# 2. See what will be created
terraform plan -var-file=envs/<env>.tfvars

# 3. Deploy
terraform apply -var-file=envs/<env>.tfvars
```

**Examples:**

```bash
# Deploy POC in us-west-2 (current production-equivalent environment)
./scripts/init.sh --env poc --profile default
terraform apply -var-file=envs/poc.tfvars

# Deploy DEV in us-east-2 (separate VPC, smaller resources)
./scripts/init.sh --env dev --profile default
terraform apply -var-file=envs/dev.tfvars
```

> ⚠️ **Always re-run `./scripts/init.sh --env <env>` when switching between environments locally.** It reconfigures Terraform's backend to point at the correct state file. Skipping this step will operate on the wrong environment's state.

### State locking — no DynamoDB

State locking uses S3's native conditional-write feature (`use_lockfile = true`). A `.tflock` object is written alongside the state file during apply and removed when the apply completes. **No DynamoDB table is required.**

---

## Planning a dev deployment (step by step)

The DEV environment lives in **`us-east-2` (Ohio)** in a **freshly-created VPC** with all core services in **private subnets**. Follow these steps before the first `apply`.

### Step 1 — Verify AWS credentials

```bash
aws sts get-caller-identity --profile default
# Must return Account: 342448511503
```

### Step 2 — Fill in region-specific values in `envs/dev.tfvars`

Two values are region-specific and need to be set before plan:

| Variable | Why | How to get it |
|---|---|---|
| `ec2_ami_id` | AMI IDs differ per region | `aws ec2 describe-images --owners amazon --region us-east-2 --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text` |
| `ec2_key_pair_name` | Key pair must exist in us-east-2 | `aws ec2 create-key-pair --key-name caltech-dev-keypair --region us-east-2 --query KeyMaterial --output text > caltech-dev-keypair.pem && chmod 400 caltech-dev-keypair.pem` |

> Even though dev uses SSM only, AWS still requires `key_name` on the EC2 resource. The key just isn't used for login.

### Step 3 — Initialize the dev backend

```bash
cd prod-stack
chmod +x scripts/init.sh
./scripts/init.sh --env dev --profile default
```

This:
- Creates the S3 state bucket (if missing).
- Reconfigures Terraform's backend to point at `caltech/dev/terraform.tfstate`.
- Runs `terraform init -reconfigure` and `terraform validate`.

### Step 4 — Generate and review the plan

```bash
terraform plan -var-file=envs/dev.tfvars -out=dev.tfplan
```

**What to check in the plan output:**

| Check | Expected result |
|---|---|
| `module.vpc[0].aws_vpc.this` | Creating new VPC `10.146.0.0/16` |
| `module.vpc[0].aws_subnet.public[*]` | 3 public subnets created |
| `module.vpc[0].aws_subnet.private[*]` | 3 private subnets created |
| `module.vpc[0].aws_nat_gateway.this[0]` | 1 NAT Gateway in public subnet |
| `module.ec2.aws_instance.app` → `subnet_id` | Points to a **private** subnet (NOT public) |
| `module.ec2_pg_sink.aws_instance.app` → `subnet_id` | Points to a **private** subnet |
| `module.ec2_redis_sink.aws_instance.app` → `subnet_id` | Points to a **private** subnet |
| `module.vpc_endpoints.aws_vpc_endpoint.ssm[*]` | 3 SSM endpoints in private subnets |
| `module.vpc_endpoints.aws_vpc_endpoint.s3` | S3 gateway endpoint attached to **both** public + private route tables |
| Resource count | Roughly **120–140 resources** to add (depends on optional modules) |
| Destroys | **Should be 0** on a fresh dev deploy |

### Step 5 — Save the plan output for review

```bash
terraform show -no-color dev.tfplan > dev.plan.txt
```

Share `dev.plan.txt` with the platform reviewer before applying.

### Step 6 — Apply when reviewed

Either deploy in one shot, or phase-by-phase using the targets in [Detailed deployment](#detailed-deployment--phase-by-phase):

```bash
terraform apply dev.tfplan
```

### Step 7 — Verify private-only access

```bash
# Get the app-server instance ID from outputs
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

# Confirm it has NO public IP
aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --region us-east-2 --profile default \
  --query 'Reservations[].Instances[].[PublicIpAddress,PrivateIpAddress,SubnetId]' \
  --output table
# PublicIpAddress should be None / empty

# Log in via SSM (no SSH key needed)
aws ssm start-session --target $INSTANCE_ID --region us-east-2 --profile default

# Inside the session — confirm outbound internet works via NAT
curl -I https://www.amazon.com
# Should return HTTP/2 200
```

### Step 8 — Common dev plan diffs to expect

| First-time message in the plan | Meaning |
|---|---|
| `+ create` against all VPC resources | Fresh VPC — expected |
| `+ create` against `aws_vpc_endpoint.ssm["ssm"]` etc. | SSM endpoints in private subnets — expected |
| `+ ec2_in_private_subnet = true` (in module diff) | The new flag is being honored — expected |

If you instead see `subnet_id = "subnet-…public…"` against EC2 — STOP. Confirm `ec2_in_private_subnet = true` is set in `envs/dev.tfvars`.

---

## Architecture

### Topology — POC (legacy, EC2 in public subnet)

> DEV and onward follow the **private-subnet topology** shown in [Network access modes](#network-access-modes-public-vs-private-subnet) — all EC2 instances live in private subnets, with SSM endpoints and NAT replacing public-subnet placement.

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS us-west-2  ·  VPC vpc-0ed44b92f11b73815                                     │
│                                                                                                              │
│  ┌─────────────────────┐   ┌──────────────────────┐   ┌─────────────────────┐   ┌──────────────────────┐   │
│  │   PUBLIC SUBNET     │   │   PRIVATE SUBNET     │   │   PRIVATE SUBNET    │   │   PRIVATE SUBNET     │   │
│  │                     │   │                      │   │                     │   │                      │   │
│  │  ┌───────────────┐  │   │ Aurora PostgreSQL    │   │ MSK Connect         │   │ ElastiCache          │   │
│  │  │  EC2 × 3      │──┼──▶│ Source (Serverless   │──▶│ Debezium Sources    │──▶│ Redis Serverless     │   │
│  │  │  • app        │  │   │  v2, 17.x)           │   │ (×5, one per table) │   │                      │   │
│  │  │  • pg_sink    │  │   │                      │   │                     │   ├──────────────────────┤   │
│  │  │  • redis_sink │  │   │                      │   │ ▼                   │   │                      │   │
│  │  └───────────────┘  │   │                      │   │ MSK Provisioned     │──▶│ Aurora PostgreSQL    │   │
│  │  VPC Endpoints      │   │                      │   │ Kafka 3.9.x         │   │ Sink Serverless v2   │   │
│  │  (SSM × 3)          │   │                      │   │ 3 Brokers (3 AZs)   │   │                      │   │
│  └─────────────────────┘   └──────────────────────┘   │ SASL/SCRAM (9096)   │   └──────────────────────┘   │
│                                                       │ + SASL/IAM (9098)   │                              │
│                                                       └─────────────────────┘                              │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data flow

```
Application       CDC Source         Event Streaming        Consumer Targets
──────────        ─────────────      ────────────────       ─────────────────────────
EC2 ──▶  Aurora Source ──▶  Debezium → MSK (Kafka)  ──┬──▶  ElastiCache Redis
         (logical repl.)                              │
                                                      ├──▶  Aurora Sink — student_enrollment
                                                      ├──▶  Aurora Sink — student_attendance
                                                      ├──▶  Aurora Sink — student_lms
                                                      ├──▶  Aurora Sink — section_enrollments
                                                      └──▶  Aurora Sink — student_term_log
```

### Deployment phases (left to right)

```
PHASE 1 — Foundation          PHASE 2              PHASE 3              PHASE 4               PHASE 5
─────────────────────────     ──────────────────   ──────────────────   ───────────────────   ─────────────────────────
vpc (optional)                ec2                  aurora_source        msk (Kafka)           elasticache (Redis target)
kms                           ec2_pg_sink     ──▶                  ──▶ msk_connect        ─▶ aurora_sink (PG target)
security_groups               ec2_redis_sink                            (5 source × 1 table)
vpc_endpoints
s3
secrets
iam
```

---

## Detailed deployment — phase by phase

> Run each phase, verify success, then move to the next. Use the same `--var-file` for every command in the same environment.

### Phase 0 — VPC (only if `create_vpc = true`)

Required for new environments (DEV, future QAS/PROD). Skipped for POC (uses existing VPC).

```bash
terraform apply -var-file=envs/dev.tfvars -target=module.vpc
```

**Creates:** VPC + 3 public + 3 private subnets + IGW + NAT Gateway + route tables.

### Phase 1 — Foundation

```bash
terraform apply -var-file=envs/<env>.tfvars -target=module.kms
terraform apply -var-file=envs/<env>.tfvars -target=module.security_groups
terraform apply -var-file=envs/<env>.tfvars -target=module.vpc_endpoints
terraform apply -var-file=envs/<env>.tfvars -target=module.s3
terraform apply -var-file=envs/<env>.tfvars -target=module.secrets
terraform apply -var-file=envs/<env>.tfvars -target=module.iam
```

### Phase 2 — App servers (EC2)

```bash
terraform apply -var-file=envs/<env>.tfvars \
  -target=module.ec2 \
  -target=module.ec2_pg_sink \
  -target=module.ec2_redis_sink
```

### Phase 3 — Source databases

```bash
# Serverless v2 source for CDC
terraform apply -var-file=envs/<env>.tfvars -target=module.aurora_source
```

### Phase 4 — Kafka + CDC pipeline

```bash
# 1. Deploy MSK cluster (takes 30–40 minutes)
terraform apply -var-file=envs/<env>.tfvars -target=module.msk

# 2. Upload Debezium plugin ZIP to S3
curl -L -o debezium-connector-postgres-2.5.0.Final-plugin.zip \
  "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.0.Final/debezium-connector-postgres-2.5.0.Final-plugin.zip"

aws s3 cp debezium-connector-postgres-2.5.0.Final-plugin.zip \
  s3://$(terraform output -raw s3_plugins_bucket)/plugins/ \
  --profile default

# 3. Deploy all 5 source connectors
terraform apply -var-file=envs/<env>.tfvars -target=module.msk_connect
```

### Phase 5 — Consumer targets

```bash
terraform apply -var-file=envs/<env>.tfvars -target=module.elasticache
terraform apply -var-file=envs/<env>.tfvars -target=module.aurora_sink
```

### Final pass

```bash
# Validates full stack consistency, tightens IAM policies
terraform apply -var-file=envs/<env>.tfvars
```

### Total deployment time (per environment)

| Phase | Estimated time |
|---|---|
| 0 — VPC (if used) | 3 min |
| 1 — Foundation | ~7 min |
| 2 — App servers | 3 min |
| 3 — Source DB | 10–15 min |
| 4 — MSK + Connect | 35–50 min |
| 5 — Consumers | 10–20 min |
| **Total** | **~1.5–2 hours** |

---

## Operations

### Connect to EC2 (no SSH needed — SSM Session Manager)

Works identically whether EC2 is in public (POC) or private (DEV/QAS/PROD) subnets — SSM uses VPC interface endpoints, never the public internet.

```bash
terraform output ec2_instance_id   # get the ID
aws ssm start-session --target <instance-id> --region <region> --profile default

# Also available:
terraform output ssm_connect_command            # app server
terraform output ssm_connect_command_pg_sink    # PG sink worker
terraform output ssm_connect_command_redis_sink # Redis sink worker
```

### Get database password from Secrets Manager

```bash
SECRET_ARN=$(terraform output -raw aurora_source_secret_arn)
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region <region> --profile default \
  --query SecretString --output text | jq -r '.password'
```

### Check MSK Connect connector status

```bash
aws kafkaconnect list-connectors --region <region> --profile default \
  --query "connectors[*].{Name:connectorName,State:connectorState}" --output table
```

### List all outputs

```bash
terraform output
```

### Switch between environments locally

```bash
# Switch to DEV
./scripts/init.sh --env dev --profile default

# Switch back to POC
./scripts/init.sh --env poc --profile default
```

The init script reconfigures Terraform's backend (`-reconfigure` flag) so the next plan/apply targets the correct state file.

---

## Adding a new environment (QAS / PROD)

The framework already accepts these env names — just create the config files.

### Step 1 — Copy DEV config as a starting point

```bash
cd prod-stack
cp envs/dev.backend.hcl envs/qas.backend.hcl
cp envs/dev.tfvars      envs/qas.tfvars
```

### Step 2 — Edit the QAS files

In `envs/qas.backend.hcl`:
```hcl
key = "caltech/qas/terraform.tfstate"    # change from "caltech/dev/..."
```

In `envs/qas.tfvars`:
- `environment = "qas"`
- `aws_region = "<chosen-region>"`
- `vpc_cidr = "10.30.0.0/16"` (avoid overlap with other envs)
- Adjust resource sizing for QAS workload (typically between dev and prod)
- Create new EC2 key pair in the QAS region; update `ec2_key_pair_name`
- Look up region-specific AMI ID; update `ec2_ami_id`

### Step 3 — Deploy

```bash
./scripts/init.sh --env qas --profile default
terraform apply -var-file=envs/qas.tfvars
```

Same procedure for PROD.

---

## Destroying an environment

```bash
# 1. Switch to the env you want to destroy
./scripts/init.sh --env <env> --profile default

# 2. Disable deletion protection on Aurora (now enabled in ALL envs, including dev)
#    Edit envs/<env>.tfvars:
#      aurora_deletion_protection = false
#      aurora_skip_final_snapshot = true   # set false to keep a final snapshot
#    Then apply the change:
terraform apply -var-file=envs/<env>.tfvars

# 3. Destroy MSK Connect connectors first (they depend on MSK, Aurora, S3)
terraform destroy -var-file=envs/<env>.tfvars -target=module.msk_connect

# 4. Destroy everything else
terraform destroy -var-file=envs/<env>.tfvars
```

> ⚠️ **Destroying PROD is irreversible.** Double-check the `--env` flag and the `terraform plan` output before typing `yes`.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform init` shows backend changed | Switched env without re-running `init.sh` | `./scripts/init.sh --env <env>` |
| `Backend configuration changed` | Same as above | Same — init script handles `-reconfigure` |
| `Lock Info: ID: ...` then hangs | Previous apply crashed, lock file stuck in S3 | `terraform force-unlock <lock-id>` |
| `InsufficientFreeAddressesInSubnet` (MSK Connect) | Subnet ran out of IPs for worker ENIs | Update `msk_connect_subnet_ids` in tfvars to a subnet with more free IPs |
| `BrokerUnreachable` on MSK Connect | MSK SG doesn't allow port 9098 from MSK Connect SG | Re-apply `module.security_groups` |
| Aurora cluster `Backing-up` blocks delete | Final snapshot in progress | Wait, then re-run destroy |
| `AccessDenied PutPublicAccessBlock` (S3) | Org SCP enforces it at account level | Expected — script warns and continues |
| `BucketAlreadyOwnedByYou` | State bucket already exists in your account | Expected — script skips creation |
| Plan shows resources to destroy you didn't expect | Wrong env active OR variable typo | Verify `./scripts/init.sh --env <env>` output before applying |

---

## Related documentation

| File | Audience | Contents |
|---|---|---|
| [README.md](README.md) | All — start here | This file — deployment guide |
| [DOCUMENTATION.md](DOCUMENTATION.md) | Platform engineers | Full operational reference: module-by-module, security model, runbooks, DR, cost |
| [`../MSK-CONNECT-CONFIG.md`](../MSK-CONNECT-CONFIG.md) | App team | Connector configuration Q&A |
| [`../ARCHITECTURE.md`](../ARCHITECTURE.md) | All | Detailed Mermaid diagrams + network view |
| [Caltech-POC-Architecture.doc](Caltech-POC-Architecture.doc) | Customer | Polished customer-facing architecture document |

---

## Support

For deployment issues or questions, contact the **Platform Team — panicleTech** with:
- Environment name (`poc` / `dev` / `qas` / `prod`)
- The exact `terraform apply` command you ran
- Full error output from Terraform
