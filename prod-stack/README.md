# Caltech POC Stack — Terraform Deployment Guide

**Region:** us-west-2 | **Account:** 342448511503 | **Profile:** `default` | **Stack:** `caltech-poc`

### What's in this stack

| Service | Instance(s) | Notes |
|---|---|---|
| **VPC + Subnets** | Optional via `create_vpc` flag | When `true`, Terraform builds a fresh VPC with 3 public + 3 private subnets, IGW, NAT. When `false`, uses an existing VPC + subnet IDs from tfvars |
| **EC2 app servers** | 3 instances | `app-server` (txn simulator) on `m6i.2xlarge`; `pg-sink-app-server` + `redis-sink-app-server` on `t3.xlarge` — all no public IP, SSM access |
| **Aurora PostgreSQL Source** | 1 cluster (Serverless v2) | CDC source with logical replication enabled |
| **Aurora PostgreSQL Source Limitless** | 1 cluster + shard group | PG `16.13-limitless`, 16–32 ACUs, sharded variant |
| **Aurora PostgreSQL Sink** | 1 cluster (Serverless v2) | JDBC sink target hydrated by 5 connectors |
| **MSK Provisioned** | 3 brokers (3 AZs) | `kafka.m5.2xlarge`, Kafka 3.9.x, 1000 GB EBS each |
| **MSK Connect** | 7 connectors | 2 Debezium sources (split tables) + 5 JDBC sinks (one per table) |
| **ElastiCache Redis** | Serverless cache | TLS always-on, KMS encrypted |
| **Supporting** | KMS (5 keys), SGs (7), VPC endpoints, S3 (3 buckets), Secrets Manager, IAM roles | All scoped to least-privilege |

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS us-west-2  ·  VPC vpc-0ed44b92f11b73815                                     │
│                                                                                                              │
│  ┌─────────────────────┐   ┌──────────────────────┐   ┌─────────────────────┐   ┌──────────────────────┐   │
│  │   PUBLIC SUBNET     │   │   PRIVATE SUBNET     │   │   PRIVATE SUBNET    │   │   PRIVATE SUBNET     │   │
│  │                     │   │                      │   │                     │   │                      │   │
│  │  ┌───────────────┐  │   │ Aurora PostgreSQL    │   │ MSK Connect         │   │ ElastiCache          │   │
│  │  │  EC2 × 3      │──┼──▶│ Source (16.x         │──▶│ Debezium Source     │──▶│ Redis Serverless     │   │
│  │  │  t3.xlarge    │  │   │  Serverless v2)      │   │ Connector           │   │                      │   │
│  │  │  • app        │  │   │                      │   │                     │   ├──────────────────────┤   │
│  │  │  • pg_sink    │  │   │ Aurora Source        │   │ ▼                   │   │                      │   │
│  │  │  • redis_sink │  │   │ Limitless            │   │ MSK Provisioned     │──▶│ Aurora PostgreSQL    │   │
│  │  └───────────────┘  │   │ (16.13-limitless)    │   │ Kafka 3.9.x         │   │ Sink Serverless v2   │   │
│  │  VPC Endpoints      │   │                      │   │ kafka.m5.2xlarge    │   │ (5 tables hydrated   │   │
│  │  (SSM × 3)          │   │                      │   │ 3 Brokers (3 AZs)   │   │  via 5 JDBC sinks)   │   │
│  └─────────────────────┘   └──────────────────────┘   │ SASL/SCRAM (9096)   │   └──────────────────────┘   │
│                                                       │ + SASL/IAM (9098)   │                              │
│                                                       └─────────────────────┘                              │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow (Left to Right)

```
Application Layer         CDC Source            Event Streaming           Consumer Targets
──────────────────        ─────────────────     ─────────────────────     ──────────────────────────
EC2 (Txn Simulator) ──▶   Aurora Source  ──▶    Debezium → MSK    ──┬──▶  ElastiCache Redis
                          (logical repl.)       Kafka 3.9.x          │
                                                Topics:              ├──▶  Aurora Sink — student_enrollment
                                                caltech_poc_10.*     ├──▶  Aurora Sink — student_attendance
                                                                     ├──▶  Aurora Sink — student_lms
                                                                     ├──▶  Aurora Sink — section_enrollments
                                                                     └──▶  Aurora Sink — student_term_log
```

### Deployment Phases (Left to Right)

```
PHASE 1 — Foundation          PHASE 2              PHASE 3                  PHASE 4               PHASE 5
─────────────────────────     ──────────────────   ──────────────────────   ───────────────────   ─────────────────────────
kms                           ec2                  aurora_source            msk (Kafka)           elasticache (Redis Sink)
security_groups    ─────────▶ ec2_pg_sink     ──▶ aurora_source_limitless ─▶ msk_connect        ─▶ aurora_sink (PG Sink)
vpc_endpoints                 ec2_redis_sink                                 (Debezium source)     msk_connect_sink × 5
s3                                                                                                (5 JDBC sink connectors)
secrets
iam
```

---

## Module Inventory (14 modules)

| # | Module | Purpose | Key resources |
|---|---|---|---|
| 0 | `vpc` | **Optional** — fresh VPC + subnets + IGW + NAT | Only created when `create_vpc = true` |
| 1 | `kms` | Service-scoped CMKs | 5 keys: ebs, s3, aurora, redis, secrets |
| 2 | `security_groups` | Least-privilege SGs | EC2, MSK, MSK Connect, Aurora ×2, ElastiCache |
| 3 | `vpc_endpoints` | Interface + Gateway | SSM, SSMMessages, EC2Messages, S3 Gateway |
| 4 | `s3` | Buckets with lifecycle | plugins, data-lake, logs |
| 5 | `secrets` | Auto-gen credentials | Aurora source + sink master passwords |
| 6 | `iam` | Service roles | EC2 instance profile, MSK Connect execution role |
| 7 | `ec2` | App server (×3 instances) | app, pg_sink, redis_sink |
| 8 | `aurora_source` | CDC source — Serverless v2 | PostgreSQL with `rds.logical_replication=1` |
| 9 | `aurora_source_limitless` | CDC source — Limitless variant | PG 16.13-limitless, 16–32 ACU shard group |
| 10 | `aurora_sink` | JDBC sink target | Serverless v2 — receives Kafka events |
| 11 | `msk` | Provisioned Kafka cluster | kafka.m5.2xlarge × **3 brokers** (3 AZs) |
| 12 | `msk_connect` | Generic connector module | Reused 7× (2 Debezium sources + 5 JDBC sinks) |
| 13 | `elasticache` | Redis cache | Serverless cache (Redis 7+) |

---

## Current Configuration

| Setting | Value |
|---|---|
| Environment | `poc` |
| **Network mode** | `create_vpc = false` (uses existing VPC below) |
| **Existing VPC** | `vpc-0ed44b92f11b73815` |
| **Existing Public Subnets** | `subnet-038946a978f266b7d`, `subnet-052b8a9527604c064` |
| **Existing Private Subnets** | `subnet-0afa40d43201113c7`, `subnet-09fbbd79068ad5555` |
| **Existing MSK Subnets (3 AZs)** | `subnet-0afa40d43201113c7`, `subnet-09fbbd79068ad5555`, `subnet-069266bf3b71d537e` |
| **New VPC defaults** (when `create_vpc = true`) | CIDR `10.0.0.0/16`; AZs `us-west-2{a,b,c}`; public `10.0.{1,2,3}.0/24`; private `10.0.{11,12,13}.0/24`; NAT enabled |
| EC2 AMI | `ami-04486bbfa25728941` |
| EC2 instance types | `app-server`: **`m6i.2xlarge`** (8 vCPU, 32 GiB) · `pg-sink-app-server` + `redis-sink-app-server`: `t3.xlarge` (4 vCPU, 16 GiB) |
| EC2 storage | 100 GB gp3 root (KMS encrypted) · no public IP |
| EC2 instances | 3 — `app-server`, `pg-sink-app-server`, `redis-sink-app-server` |
| EC2 Access | SSM via VPC endpoints (no SSH keys, no public IP) |
| SSH Allowed CIDR | `10.145.0.0/24` (VM subnet only) |
| Aurora Source | PostgreSQL Serverless v2 (16.x), 0.5–16 ACUs |
| Aurora Source Limitless | PostgreSQL 16.13-limitless, 16–32 ACU shard group |
| Aurora Sink | PostgreSQL Serverless v2 (16.x) |
| MSK Type | Provisioned · Kafka 3.9.x · `kafka.m5.2xlarge` |
| MSK Brokers | **3** (one per AZ — `us-west-2a`, `us-west-2b`, `us-west-2c`) |
| MSK Auth | SASL/SCRAM port 9096 (app clients) + SASL/IAM port 9098 (MSK Connect) |
| MSK Storage | 1000 GB per broker |
| Sink connectors | 5 JDBC sinks — one per source table |
| State Bucket | `caltech-terraform-state-342448511503` |

---

## Quick Start

```bash
cd prod-stack
chmod +x scripts/init.sh
./scripts/init.sh --profile default
```

Creates S3 state bucket, DynamoDB lock table, runs `terraform init -upgrade` and `terraform validate`.

---

## Network Modes (VPC: use existing OR create new)

The stack supports two network deployment modes, controlled by one flag in `terraform.tfvars`:

```hcl
create_vpc = false   # default — use the existing VPC (current production)
# OR
create_vpc = true    # Terraform builds a new VPC + subnets + IGW + NAT
```

### Mode A — Existing VPC (default, current production)

```hcl
# terraform.tfvars
create_vpc             = false
vpc_id                 = "vpc-0ed44b92f11b73815"
public_subnet_ids      = ["subnet-038946a978f266b7d", "subnet-052b8a9527604c064"]
private_subnet_ids     = ["subnet-0afa40d43201113c7", "subnet-09fbbd79068ad5555"]
msk_subnet_ids         = ["subnet-0afa40d43201113c7", "subnet-09fbbd79068ad5555", "subnet-069266bf3b71d537e"]
elasticache_subnet_ids = ["subnet-09fbbd79068ad5555", "subnet-069266bf3b71d537e"]
```

All modules deploy into the existing VPC. This is the current production deployment — leave it set this way unless you're spinning up a new environment.

### Mode B — Fresh VPC (new environment)

```hcl
# terraform.tfvars
create_vpc           = true
vpc_cidr             = "10.0.0.0/16"                                  # any non-overlapping CIDR
availability_zones   = ["us-west-2a", "us-west-2b", "us-west-2c"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
enable_nat_gateway   = true
```

When `create_vpc = true`:
- `module.vpc` creates the VPC, 3 public + 3 private subnets, Internet Gateway, NAT Gateway, route tables
- All downstream modules (security_groups, EC2, Aurora, MSK, etc.) automatically use the new VPC via `locals.*`
- The existing `vpc_id` / `*_subnet_ids` values are ignored

⚠️ **Do NOT flip `create_vpc = true` on the existing deployment.** It will try to move every resource to the new VPC, destroying the production stack. Use this mode only for fresh deployments (new account, new region, or testing — see [Testing the VPC module safely](#testing-the-vpc-module-safely) below).

### Testing the VPC module safely

To test the new VPC without disturbing production:

```bash
# 1. Set in tfvars
create_vpc = true
vpc_cidr   = "10.160.0.0/16"   # any non-overlapping CIDR

# 2. Apply ONLY the VPC module — never do a full apply while testing
terraform apply -target=module.vpc

# 3. Verify in the AWS console (look for caltech-poc-vpc, subnets, IGW, NAT)

# 4. Destroy the test VPC
terraform destroy -target=module.vpc

# 5. Revert
create_vpc = false
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x |
| AWS Provider | >= 5.95.0 (required for Aurora Limitless `cluster_scalability_type`) |
| AWS Profile | `default` configured in `~/.aws/credentials` |
| EC2 Key Pair | `caltech-keypair` created in AWS console (us-west-2) |
| Debezium ZIP | Must be uploaded to S3 before MSK Connect step |

```bash
terraform version                                # >= 1.5.0
aws --version                                    # >= 2.x
aws sts get-caller-identity --profile default    # verify auth → Account: 342448511503
```

---

## Sequential Deployment (Left to Right)

**Deploy each step in order. Verify success before moving to the next.**

---

## PHASE 0: Network (only if `create_vpc = true`)

Skip this phase entirely if `create_vpc = false` (you're using an existing VPC).

```bash
terraform apply -target=module.vpc
```

**What gets created:**
- 1 VPC (`caltech-poc-vpc`) with DNS hostnames enabled
- 3 public subnets (one per AZ — `us-west-2a`, `2b`, `2c`)
- 3 private subnets (one per AZ)
- 1 Internet Gateway
- 1 NAT Gateway (with Elastic IP, in first public subnet — cost-optimized single NAT)
- Public route table (default route → IGW) with associations
- Private route table (default route → NAT) with associations

**Verify:**
```bash
terraform output vpc_id
terraform output public_subnet_ids
terraform output private_subnet_ids
terraform output nat_gateway_eip
```

After this, the `locals` automatically wire all downstream modules to use the new VPC's subnet IDs. Proceed to Phase 1.

---

## PHASE 1: Foundation

### 1.1 — KMS Encryption Keys

```bash
terraform apply -target=module.kms
```

| Key alias | Used by |
|---|---|
| `alias/caltech-poc-ebs` | EC2 root volumes (× 3) |
| `alias/caltech-poc-s3` | S3 buckets |
| `alias/caltech-poc-aurora` | All 3 Aurora clusters (source, sink, limitless) |
| `alias/caltech-poc-redis` | ElastiCache |
| `alias/caltech-poc-secrets` | Secrets Manager + MSK SCRAM secret |

---

### 1.2 — Security Groups

```bash
terraform apply -target=module.security_groups
```

| Security Group | Inbound | Outbound |
|---|---|---|
| `caltech-poc-ec2-sg` | SSH 22 from `10.145.0.0/24`; App 8080 from `10.145.0.0/24` | All |
| `caltech-poc-vpce-sg` | HTTPS 443 from VPC CIDR | All |
| `caltech-poc-msk-sg` | 9098 IAM + 9096 SCRAM from EC2 + MSK Connect; 9092/9094 from MSK Connect | All |
| `caltech-poc-msk-connect-sg` | None | All |
| `caltech-poc-aurora-source-sg` | 5432 from EC2 + MSK Connect + VM CIDR | All |
| `caltech-poc-aurora-sink-sg` | 5432 from EC2 + MSK Connect + VM CIDR | All |
| `caltech-poc-elasticache-sg` | 6379 from EC2 + VM CIDR | All |

---

### 1.3 — VPC Endpoints (SSM + S3)

> Required — EC2 has no public IP, so SSM agent cannot reach AWS endpoints over the internet.

```bash
terraform apply -target=module.vpc_endpoints
```

Creates 3 interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) in the public subnets and 1 S3 Gateway endpoint on the public route tables.

> **Note:** STS, SecretsManager, and the private-subnet S3 Gateway endpoint already exist in the VPC (managed outside this stack). MSK Connect workers in private subnets use those existing endpoints.

---

### 1.4 — S3 Buckets

> `PutPublicAccessBlock` and `PutBucketPolicy` are skipped — enforced by the org SCP at account level.

```bash
terraform apply -target=module.s3
```

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `caltech-poc-msk-plugins` | Debezium connector ZIP | Versioned, KMS encrypted |
| `caltech-poc-data-lake` | Kafka consumer event archive | 30d → IA, 90d → Glacier |
| `caltech-poc-msk-logs` | MSK Connect worker logs | Expire after 90d |

---

### 1.5 — Secrets Manager

```bash
terraform apply -target=module.secrets
```

Generates random 32-character passwords — never stored in Terraform state.

| Secret | Used for |
|---|---|
| `caltech-poc-aurora-source-password` | Aurora Source master password (also reused by Limitless) |
| `caltech-poc-aurora-sink-password` | Aurora Sink master password |
| `AmazonMSK_caltech-poc-scram` (created by `msk` module) | MSK SASL/SCRAM credentials |

---

### 1.6 — IAM Roles

```bash
terraform apply -target=module.iam
```

| Role | Trust | Permissions |
|---|---|---|
| `caltech-poc-ec2-app-role` | ec2.amazonaws.com | SSM · MSK SASL/IAM · Secrets read · S3 read/write |
| `caltech-poc-msk-connect-role` | kafkaconnect.amazonaws.com | MSK SASL/IAM · S3 plugin+logs · Secrets read · VPC |

---

## PHASE 2: App Servers

### 2.1 — EC2 App Server (Transaction Simulator)

```bash
terraform apply -target=module.ec2
```

- `caltech-poc-app-server` · **`m6i.2xlarge`** (8 vCPU, 32 GiB RAM) · 100 GB gp3 (KMS encrypted)
- Public subnet, **no public IP** — SSM access only
- Heavier instance type because this server runs the transaction simulator (write-heavy workload)

### 2.2 — EC2 PG Sink Server

```bash
terraform apply -target=module.ec2_pg_sink
```

- `caltech-poc-pg-sink-app-server` · same template
- Runs PG sink consumer logic

### 2.3 — EC2 Redis Sink Server

```bash
terraform apply -target=module.ec2_redis_sink
```

- `caltech-poc-redis-sink-app-server` · same template
- Runs Redis sink consumer logic

**Connect via SSM (any instance):**

```bash
aws ssm start-session \
  --target $(terraform output -raw ec2_instance_id) \
  --region us-west-2 --profile default
```

---

## PHASE 3: Source Databases

### 3.1 — Aurora PostgreSQL Source (Serverless v2)

> Takes 5–15 minutes.

```bash
terraform apply -target=module.aurora_source
```

- `caltech-poc-aurora-source` · Serverless v2 (0.5–16 ACUs)
- Logical replication: `rds.logical_replication=1`, `max_replication_slots=10`, `max_wal_senders=10`
- KMS encrypted · CloudWatch Logs · Deletion protection ON

### 3.2 — Aurora PostgreSQL Source Limitless

> Takes 20–40 minutes.

```bash
terraform apply -target=module.aurora_source_limitless
```

- `caltech-poc-aurora-source-limitless` · Aurora Limitless (16.13-limitless)
- Shard group `caltech-poc-aurora-source-limitless-shard` (16–32 ACUs)
- Performance Insights + Enhanced Monitoring enabled (Limitless requirement)
- I/O-Optimized storage (Limitless requirement)
- **Provisioned via AWS CLI through `null_resource`** to bypass an AWS provider bug that sends `engine_mode=provisioned` (which Limitless rejects)

---

## PHASE 4: CDC Pipeline

### 4.1 — MSK Provisioned (Kafka)

> Takes 30–40 minutes.

```bash
terraform apply -target=module.msk
```

- `caltech-poc-msk` · Kafka 3.9.x · **3 brokers** (`kafka.m5.2xlarge`, 1000 GB EBS each, one per AZ)
- SASL/SCRAM (port 9096) + SASL/IAM (port 9098)
- Custom config: `auto.create.topics.enable=true`, `default.replication.factor=3`, `min.insync.replicas=2`
- CloudWatch broker logs

### 4.2 — Upload Debezium Plugin

```bash
curl -L -o debezium-connector-postgres-2.5.0.Final-plugin.zip \
  "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.0.Final/debezium-connector-postgres-2.5.0.Final-plugin.zip"

aws s3 cp debezium-connector-postgres-2.5.0.Final-plugin.zip \
  s3://$(terraform output -raw s3_plugins_bucket)/plugins/ \
  --profile default
```

A separate **JDBC sink plugin** (Confluent JDBC Sink) must also be uploaded for the sink connectors.

### 4.3 — MSK Connect — Debezium Source Connector

> Takes 5–10 minutes.

```bash
terraform apply -target=module.msk_connect
```

- Connector name: `caltech-poc-debezium-postgres-source-connector`
- Authenticates to MSK via IAM (port 9098)
- Publishes CDC events to topics `caltech_poc_10.public.<table>`
- Uses `ExtractNewRecordState` transform (schema-less JSON output)

---

## PHASE 5: Consumer Targets

### 5.1 — ElastiCache Redis Serverless

```bash
terraform apply -target=module.elasticache
```

`caltech-poc-redis` · TLS always-on · KMS encrypted.

### 5.2 — Aurora PostgreSQL Sink

> Takes 5–15 minutes.

```bash
terraform apply -target=module.aurora_sink
```

`caltech-poc-aurora-sink` · Serverless v2 · KMS encrypted · Deletion protection ON.

### 5.3 — MSK Connect — 5 JDBC Sink Connectors

```bash
terraform apply \
  -target=module.msk_connect_sink \
  -target=module.msk_connect_sink_attendance \
  -target=module.msk_connect_sink_lms \
  -target=module.msk_connect_sink_section_enrollments \
  -target=module.msk_connect_sink_term_log
```

| Module | Connector name | Source topic | Sink table |
|---|---|---|---|
| `msk_connect_sink` | `postgres-sink-connector-student-enrollment` | `caltech_poc_10.public.student_enrollment` | `student_enrollment` |
| `msk_connect_sink_attendance` | `postgres-sink-connector-student-attendance` | `caltech_poc_10.public.student_attendance` | `student_attendance` |
| `msk_connect_sink_lms` | `postgres-sink-connector-student-lms` | `caltech_poc_10.public.student_lms` | `student_lms` |
| `msk_connect_sink_section_enrollments` | `postgres-sink-connector-section-enrollments` | `caltech_poc_10.public.section_enrollments` | `section_enrollments` |
| `msk_connect_sink_term_log` | `postgres-sink-connector-student-term-log` | `caltech_poc_10.public.student_term_log` | `student_term_log` |

All sink connectors use `schemas.enable=false` (matching the source connector output) and `pk.mode=record_key`.

---

## PHASE 6: Final Pass

```bash
terraform apply
```

Tightens IAM MSK policy from `*` to the exact cluster ARN. Validates full stack consistency.

---

## Deployment Summary Table

| Phase | Module | Command | Est. Time |
|---|---|---|---|
| Network (optional) | vpc | `terraform apply -target=module.vpc` *(only if `create_vpc = true`)* | 3 min |
| Foundation | kms | `terraform apply -target=module.kms` | 1 min |
| Foundation | security_groups | `terraform apply -target=module.security_groups` | 1 min |
| Foundation | vpc_endpoints | `terraform apply -target=module.vpc_endpoints` | 2 min |
| Foundation | s3 | `terraform apply -target=module.s3` | 1 min |
| Foundation | secrets | `terraform apply -target=module.secrets` | 1 min |
| Foundation | iam | `terraform apply -target=module.iam` | 1 min |
| App | ec2 (× 3 modules) | `terraform apply -target=module.ec2 -target=module.ec2_pg_sink -target=module.ec2_redis_sink` | 3 min |
| Source DB | aurora_source | `terraform apply -target=module.aurora_source` | 5–15 min |
| Source DB | aurora_source_limitless | `terraform apply -target=module.aurora_source_limitless` | 20–40 min |
| CDC | msk | `terraform apply -target=module.msk` | 30–40 min |
| CDC | msk_connect | Upload ZIP then `terraform apply -target=module.msk_connect` | 5–10 min |
| Consumers | elasticache | `terraform apply -target=module.elasticache` | 2 min |
| Consumers | aurora_sink | `terraform apply -target=module.aurora_sink` | 5–15 min |
| Consumers | msk_connect_sink × 5 | `terraform apply -target=module.msk_connect_sink...` | 5–10 min each |
| Final | (full apply) | `terraform apply` | 1 min |

**Total wall-clock time:** ~2.5 hours for a fresh deployment.

---

## File Structure

```
prod-stack/
├── main.tf                  # Root orchestrator — calls all 13 modules
├── variables.tf             # All input variables with descriptions and defaults
├── outputs.tf               # All stack outputs
├── data.tf                  # AWS account identity + route table data sources
├── versions.tf              # Provider constraints (aws ≥ 5.95, random, null)
├── providers.tf             # AWS provider + default_tags
├── backend.hcl              # Backend config: bucket, key, region, profile
├── terraform.tfvars         # Active config — all real IDs filled in
├── scripts/
│   └── init.sh              # Bootstrap script (cross-platform: Linux, macOS, Windows MINGW64)
│
└── modules/
    ├── vpc/                 # NEW: VPC + 3 public + 3 private subnets + IGW + NAT (opt-in)
    ├── kms/                 # 5 service-scoped CMKs
    ├── security_groups/     # 7 SGs with least-privilege rules
    ├── vpc_endpoints/       # SSM interface endpoints + S3 Gateway
    ├── s3/                  # 3 buckets (plugins, data-lake, logs)
    ├── secrets/             # Aurora master passwords
    ├── iam/                 # EC2 instance profile + MSK Connect execution role
    ├── ec2/                 # App server template (used 3× for app, pg_sink, redis_sink)
    ├── aurora_source/       # Serverless v2 with logical replication
    ├── aurora_source_limitless/  # Limitless variant via null_resource + AWS CLI
    ├── aurora_sink/         # Serverless v2 sink target
    ├── msk/                 # Provisioned Kafka with broker config
    ├── msk_connect/         # Generic MSK Connect connector (reused 7×)
    └── elasticache/         # Redis Serverless cache
```

---

## MSK Broker Configuration

**3 brokers** (one per AZ for HA) — configured via:

```hcl
# In terraform.tfvars
msk_broker_count       = 3
msk_subnet_ids         = ["subnet-0afa40d43201113c7", "subnet-09fbbd79068ad5555", "subnet-069266bf3b71d537e"]
```

Each broker lives in a different AZ (`us-west-2a`, `us-west-2b`, `us-west-2c`) to satisfy `min.insync.replicas = 2` and `default.replication.factor = 3` for fault tolerance. To scale brokers, change `msk_broker_count` and run:

```bash
terraform apply -target=module.msk
```

---

## Common Issues

| Issue | Cause | Fix |
|---|---|---|
| `AccessDenied PutPublicAccessBlock` | Org SCP — expected | Script warns and continues. Buckets are private via org policy |
| `AccessDenied PutBucketPolicy` | Org SCP — expected | Removed from S3 module. Org policy enforces account isolation |
| SSM agent offline | No public IP + VPC endpoints not deployed | Deploy `module.vpc_endpoints` then wait 2 min |
| `BucketAlreadyExists` | Bucket name taken by another account | Script suggests `caltech-terraform-state-<account-id>` |
| MSK Connect `BrokerUnreachable` | MSK SG missing inbound 9098 from MSK Connect SG | Re-apply `module.security_groups` |
| Sink connector `ConnectorNotReady: 2 failed tasks` | Aurora Sink SG missing 5432 from MSK Connect SG | Already fixed in `modules/security_groups/main.tf` |
| Aurora Limitless `engine_mode not supported` | AWS provider bug — sends `engine_mode=provisioned` default | Module uses `null_resource` + AWS CLI to bypass; no fix needed |
| Sink connector `JsonConverter requires schema and payload` | `schemas.enable=true` on sink but source produces schema-less JSON | All sink connectors set `converter_schemas_enabled = false` |
| `InvalidPermission.Duplicate` on SG apply | Rule was manually added in AWS console | Remove from code OR delete manual rule in console |
| Aurora timeout | Normal — takes 5–15 min (Limitless: 20–40 min) | Wait, then rerun apply |
| `Secret already exists` | Recovery window active | Set `secret_recovery_window_days = 0` and reapply |
| `Error acquiring state lock` | Previous run crashed | `terraform force-unlock <lock-id>` |
| Old worker config can't be deleted | A connector outside Terraform is using it | Delete the orphan connector in MSK console first |

---

## Destroying the Stack

```bash
# Step 1 — Disable deletion protection on Aurora clusters
terraform apply \
  -target=module.aurora_source \
  -target=module.aurora_sink \
  -var="aurora_deletion_protection=false" \
  -var="aurora_skip_final_snapshot=true"

# Step 2 — Destroy all sink connectors first
terraform destroy \
  -target=module.msk_connect_sink \
  -target=module.msk_connect_sink_attendance \
  -target=module.msk_connect_sink_lms \
  -target=module.msk_connect_sink_section_enrollments \
  -target=module.msk_connect_sink_term_log \
  -target=module.msk_connect

# Step 3 — Destroy Aurora Limitless (runs destroy provisioners via AWS CLI)
terraform destroy -target=module.aurora_source_limitless

# Step 4 — Destroy everything else (will also destroy module.vpc if create_vpc = true)
terraform destroy
```

> If you only need to tear down the VPC test (when `create_vpc = true` and nothing else was deployed):
> ```bash
> terraform destroy -target=module.vpc
> ```

---

## Security Notes

- **No public IP on EC2** — accessible only via SSM Session Manager (no SSH keys required)
- **SSM via VPC endpoints** — SSM traffic stays on AWS private network
- **IMDSv2 enforced** — prevents SSRF-based credential theft on EC2
- **MSK dual auth** — SASL/SCRAM (port 9096) for app clients, IAM (port 9098) for MSK Connect
- **SCRAM credentials** — auto-generated in Secrets Manager as `AmazonMSK_caltech-poc-scram`
- **KMS CMK per service** — ebs, s3, aurora, redis, secrets each have their own key
- **Org SCP enforced** — public access block and bucket policies managed at org level, not per-bucket
- **Deletion protection** — Aurora clusters default to `deletion_protection = true`
- **IAM least-privilege** — MSK policy tightened to exact cluster ARN on final `terraform apply`
- **VM CIDR allowed** — `10.145.0.0/24` allowed inbound on Aurora (5432) and Redis (6379) for on-prem VM access

---

## Related Documentation

| File | Purpose |
|---|---|
| [`../README.md`](../README.md) | Project-level overview (root) |
| [`../ARCHITECTURE.md`](../ARCHITECTURE.md) | Mermaid diagrams + detailed network view |
| [`DOCUMENTATION.md`](./DOCUMENTATION.md) | Full deployment + operations reference (this stack) |
| [`../MSK-CONNECT-CONFIG.md`](../MSK-CONNECT-CONFIG.md) | MSK + connector config Q&A for the app team |
