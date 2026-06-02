# Caltech POC — AWS CDC Pipeline Infrastructure

> **Client:** Caltech / TCS · **Region:** `us-west-2` · **Account:** `342448511503` · **Stack name:** `caltech-poc`
> **IaC:** Terraform ≥ 1.5 · AWS Provider ≥ 5.95 · **State backend:** S3 + DynamoDB lock

A production-grade AWS infrastructure that streams row-level changes from a source PostgreSQL database into both a PostgreSQL sink and a Redis cache via Debezium Change Data Capture and a Kafka event bus (Amazon MSK). The entire stack is deployed left-to-right in 6 sequential phases.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Flow](#data-flow)
3. [Module Inventory](#module-inventory)
4. [Repository Structure](#repository-structure)
5. [Network Topology](#network-topology)
6. [Security Model](#security-model)
7. [Deployment](#deployment)
8. [Operations](#operations)
9. [Outputs](#outputs)
10. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS us-west-2  ·  VPC vpc-0ed44b92f11b73815                                   │
│                                                                                                            │
│  ┌─────────────────────┐   ┌──────────────────────┐   ┌─────────────────────┐   ┌────────────────────┐   │
│  │   PUBLIC SUBNET     │   │   PRIVATE SUBNET     │   │   PRIVATE SUBNET    │   │   PRIVATE SUBNET   │   │
│  │                     │   │                      │   │                     │   │                    │   │
│  │  ┌───────────────┐  │   │ Aurora PostgreSQL    │   │ MSK Connect         │   │ ElastiCache        │   │
│  │  │  EC2 ×3       │──┼──▶│ Source DB (16.x      │──▶│ Debezium Source     │──▶│ Redis Serverless   │   │
│  │  │  t3.xlarge    │  │   │ Serverless v2)       │   │ Connector           │   │ (Redis Sink)       │   │
│  │  │  • app        │  │   │                      │   │                     │   ├────────────────────┤   │
│  │  │  • pg_sink    │  │   │ Aurora PostgreSQL    │   │ ▼                   │   │                    │   │
│  │  │  • redis_sink │  │   │ Source Limitless     │   │ MSK Provisioned     │──▶│ Aurora PostgreSQL  │   │
│  │  └───────────────┘  │   │ (16.13-limitless)    │   │ Kafka 3.9.x         │   │ Sink DB            │   │
│  │  VPC Endpoints      │   │                      │   │ kafka.m5.2xlarge    │   │ (Serverless v2)    │   │
│  │  (SSM × 3)          │   │                      │   │ 2 Brokers           │   │                    │   │
│  └─────────────────────┘   └──────────────────────┘   │ SASL/IAM (9098)     │   └────────────────────┘   │
│                                                       │ + SASL/SCRAM (9096) │                            │
│                                                       │                     │   ┌────────────────────┐   │
│                                                       │ 5 JDBC Sink         │──▶│ (writes back to    │   │
│                                                       │ Connectors          │   │  Aurora Sink — 5   │   │
│                                                       │                     │   │  tables)           │   │
│                                                       └─────────────────────┘   └────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

### CDC Pipeline (left to right)

```
Application Layer            CDC Source                Event Streaming            Consumer Targets
─────────────────────        ─────────────────         ─────────────────────      ─────────────────────────────
EC2 (Txn Simulator)   ──▶    Aurora Source     ──▶    Debezium → MSK      ──┬──▶ ElastiCache Redis (cache)
   writes rows               (logical repl.)          Kafka 3.9.x            │
                                                      Topics:                ├──▶ Aurora Sink — student_enrollment
                                                      caltech_poc_10.*       ├──▶ Aurora Sink — student_attendance
                                                                             ├──▶ Aurora Sink — student_lms
                                                                             ├──▶ Aurora Sink — section_enrollments
                                                                             └──▶ Aurora Sink — student_term_log
```

### Sink connectors (one per table)

| Connector | Source topic | Sink table |
|---|---|---|
| `postgres-sink-connector-student-enrollment` | `caltech_poc_10.public.student_enrollment` | `student_enrollment` |
| `postgres-sink-connector-student-attendance` | `caltech_poc_10.public.student_attendance` | `student_attendance` |
| `postgres-sink-connector-student-lms` | `caltech_poc_10.public.student_lms` | `student_lms` |
| `postgres-sink-connector-section-enrollments` | `caltech_poc_10.public.section_enrollments` | `section_enrollments` |
| `postgres-sink-connector-student-term-log` | `caltech_poc_10.public.student_term_log` | `student_term_log` |

---

## Module Inventory

All modules live under [`prod-stack/modules/`](./prod-stack/modules/). They are wired together in [`prod-stack/main.tf`](./prod-stack/main.tf).

| # | Module | Purpose | Key resources |
|---|---|---|---|
| 1 | [`kms`](./prod-stack/modules/kms/) | KMS keys for envelope encryption | 5 keys: aurora, secrets, s3, ebs, redis |
| 2 | [`security_groups`](./prod-stack/modules/security_groups/) | Least-privilege SGs per service | EC2, MSK, MSK Connect, Aurora Source/Sink, ElastiCache |
| 3 | [`vpc_endpoints`](./prod-stack/modules/vpc_endpoints/) | Interface + Gateway endpoints | SSM, SSMMessages, EC2Messages, S3 Gateway |
| 4 | [`s3`](./prod-stack/modules/s3/) | Buckets with lifecycle policies | `plugins`, `data-lake`, `logs` |
| 5 | [`secrets`](./prod-stack/modules/secrets/) | Auto-generated DB passwords | Aurora source + sink master credentials |
| 6 | [`iam`](./prod-stack/modules/iam/) | Roles and policies | EC2 instance profile, MSK Connect execution role |
| 7 | [`ec2`](./prod-stack/modules/ec2/) | Application server template | App + pg_sink + redis_sink (3 instances) |
| 8 | [`aurora_source`](./prod-stack/modules/aurora_source/) | CDC source — Serverless v2 | PostgreSQL 16.x with `rds.logical_replication=1` |
| 9 | [`aurora_source_limitless`](./prod-stack/modules/aurora_source_limitless/) | CDC source — Limitless variant | PostgreSQL 16.13-limitless + shard group (24–384 ACU) |
| 10 | [`aurora_sink`](./prod-stack/modules/aurora_sink/) | JDBC sink target | Serverless v2 — receives Kafka events |
| 11 | [`msk`](./prod-stack/modules/msk/) | Kafka cluster | Provisioned MSK, kafka.m5.2xlarge × 2 brokers |
| 12 | [`msk_connect`](./prod-stack/modules/msk_connect/) | Generic connector | Reused 6× — 1 Debezium source + 5 JDBC sinks |
| 13 | [`elasticache`](./prod-stack/modules/elasticache/) | Redis cache | Serverless cache (Redis 7+) |

---

## Repository Structure

```
CaliforniaProject/
│
├── README.md                       # This file — high-level overview
├── ARCHITECTURE.md                 # Mermaid diagrams + detailed network view
├── DOCUMENTATION.md                # Full deployment + operations reference
├── MSK-CONNECT-CONFIG.md           # Connector config Q&A for the app team
│
└── prod-stack/
    ├── README.md                   # Deployment guide (deployment phases, commands)
    ├── versions.tf                 # Required providers (aws ≥ 5.95, random, null)
    ├── providers.tf                # AWS provider with default tags
    ├── backend.tf                  # S3 + DynamoDB lock backend
    ├── backend.hcl                 # Backend config (separate from code)
    ├── variables.tf                # All input variables with defaults
    ├── terraform.tfvars            # Caltech-specific values
    ├── data.tf                     # aws_caller_identity, route tables lookup
    ├── main.tf                     # All module instantiations (sequenced)
    ├── outputs.tf                  # Endpoint + ARN outputs
    │
    ├── scripts/
    │   └── init.sh                 # Bootstrap state bucket + DynamoDB, run init
    │
    └── modules/                    # 13 modules — one folder each
        ├── aurora_sink/
        ├── aurora_source/
        ├── aurora_source_limitless/
        ├── ec2/
        ├── elasticache/
        ├── iam/
        ├── kms/
        ├── msk/
        ├── msk_connect/
        ├── s3/
        ├── secrets/
        ├── security_groups/
        └── vpc_endpoints/
```

---

## Network Topology

```
VPC vpc-0ed44b92f11b73815  (existing — not created by Terraform)
│
├── Public subnet (10.145.x.0/24)
│   ├── EC2 app server (no public IP — SSM access only)
│   ├── EC2 pg_sink
│   ├── EC2 redis_sink
│   └── VPC interface endpoints (SSM, SSMMessages, EC2Messages)
│
└── Private subnets (× 3 — one per AZ)
    ├── Aurora Source (Serverless v2)
    ├── Aurora Source Limitless (sharded)
    ├── Aurora Sink (Serverless v2)
    ├── MSK Provisioned (2 brokers, kafka.m5.2xlarge)
    ├── MSK Connect workers (Debezium + 5 JDBC sinks)
    └── ElastiCache Serverless Redis
```

**External CIDR allowed for VM access:** `10.145.0.0/24` — used in security group rules for PostgreSQL (5432) and Redis (6379) from on-prem VMs.

---

## Security Model

### Encryption

| Service | At rest | In transit |
|---|---|---|
| Aurora Source / Sink / Limitless | KMS (aurora key) | TLS (`rds.force_ssl=1`) |
| MSK Provisioned | KMS (secrets key) | TLS — broker↔client, in-cluster |
| ElastiCache | KMS (redis key) | TLS (always-on) |
| S3 buckets | KMS (s3 key) | TLS |
| EBS volumes | KMS (ebs key) | n/a |
| Secrets Manager | KMS (secrets key) | TLS |

### Authentication

| Path | Method |
|---|---|
| EC2 → MSK | SASL/SCRAM (port 9096) with Secrets Manager-stored credentials |
| MSK Connect workers → MSK | SASL/IAM (port 9098) via execution role |
| EC2 → Aurora (any) | PostgreSQL password from Secrets Manager |
| MSK Connect → Aurora Source | PostgreSQL password from Secrets Manager (Debezium config) |
| MSK Connect → Aurora Sink | PostgreSQL password from Secrets Manager (JDBC config) |
| App engineer → EC2 | AWS SSM Session Manager (no SSH keys, no public IP) |

### Credential handling

- **No plain-text passwords in code or tfvars.** Aurora master passwords are auto-generated by `random_password` and stored only in Secrets Manager.
- **MSK SCRAM secret** is auto-generated and associated with the cluster via `aws_msk_scram_secret_association`.
- **MSK Connect execution role** has scoped permissions: read SCRAM secret, write CloudWatch logs, connect to MSK, read S3 plugin bucket.

### Network isolation

- Aurora and ElastiCache live in **private subnets with no internet route**.
- EC2 instances are placed in the public subnet but have **no public IP** — accessed via SSM Session Manager through interface VPC endpoints.
- Aurora SG inbound is restricted to EC2 SG, MSK Connect SG, and the VM CIDR (`10.145.0.0/24`).

---

## Deployment

### Prerequisites

| Tool | Min version |
|---|---|
| Terraform | 1.5.0 |
| AWS CLI | 2.x |
| AWS credentials | IAM user/role with admin or scoped permissions on us-west-2 |
| Existing VPC + subnets | Set IDs in `terraform.tfvars` |

### One-time bootstrap

The init script creates the S3 state bucket and DynamoDB lock table, then runs `terraform init` and `terraform validate`:

```bash
cd prod-stack/
chmod +x scripts/init.sh
./scripts/init.sh --profile caltect-account
```

### Deployment sequence (6 phases, left to right)

```bash
# Phase 1 — Foundation
terraform apply -target=module.kms
terraform apply -target=module.security_groups
terraform apply -target=module.vpc_endpoints
terraform apply -target=module.s3
terraform apply -target=module.secrets
terraform apply -target=module.iam            # uses msk_cluster_arn="*" initially

# Phase 2 — App server (leftmost in diagram)
terraform apply -target=module.ec2
terraform apply -target=module.ec2_pg_sink
terraform apply -target=module.ec2_redis_sink

# Phase 3 — Source DBs
terraform apply -target=module.aurora_source
terraform apply -target=module.aurora_source_limitless

# Phase 4 — CDC pipeline (Debezium → MSK Connect → Kafka)
terraform apply -target=module.msk             # ~30–40 min
# Upload Debezium plugin ZIP to S3:
# aws s3 cp debezium-connector-postgres-*-plugin.zip \
#   s3://$(terraform output -raw s3_plugins_bucket)/plugins/ \
#   --profile caltect-account
terraform apply -target=module.msk_connect     # source connector

# Phase 5 — Consumer targets
terraform apply -target=module.elasticache
terraform apply -target=module.aurora_sink
terraform apply -target=module.msk_connect_sink
terraform apply -target=module.msk_connect_sink_attendance
terraform apply -target=module.msk_connect_sink_lms
terraform apply -target=module.msk_connect_sink_section_enrollments
terraform apply -target=module.msk_connect_sink_term_log

# Phase 6 — Final pass (tighten IAM)
terraform apply                                # IAM MSK policy from * → exact cluster ARN
```

---

## Operations

### SSM into an EC2 instance

```bash
# Get the instance ID
terraform output ec2_instance_id

# Open SSM session (no SSH needed)
$(terraform output -raw ssm_connect_command)
```

### Get a database password

```bash
SECRET_ARN=$(terraform output -raw aurora_source_secret_arn)
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region us-west-2 \
  --query SecretString --output text | jq -r '.password'
```

### Check MSK Connect connector status

```bash
aws kafkaconnect describe-connector \
  --connector-arn $(terraform output -raw debezium_connector_arn) \
  --region us-west-2 \
  --query "ConnectorState"
```

Possible states: `CREATING` → `RUNNING` (good) or `FAILED`. If `FAILED`, check CloudWatch logs at `/aws/mskconnect/<connector-name>`.

### Aurora Limitless capacity

The Limitless shard group is configured for **24–384 ACUs** (48 GiB to 768 GiB RAM equivalent). It scales horizontally — to change the range:

```bash
aws rds modify-db-shard-group \
  --db-shard-group-identifier caltech-poc-aurora-source-limitless-shard \
  --max-acu 512 \
  --min-acu 24 \
  --region us-west-2
```

---

## Outputs

After a successful full deploy, these outputs are available:

| Output | Description |
|---|---|
| `ec2_instance_id` / `ec2_public_ip` | App server instance |
| `ec2_pg_sink_instance_id` / `ec2_redis_sink_instance_id` | Additional sink-side EC2 |
| `ssm_connect_command*` | One-liner to SSM into each EC2 |
| `msk_cluster_arn` | MSK Provisioned cluster ARN |
| `msk_bootstrap_brokers` | SASL/SCRAM bootstrap endpoint (port 9096) |
| `aurora_source_endpoint` | Aurora Source write endpoint |
| `aurora_sink_endpoint` | Aurora Sink write endpoint |
| `aurora_source_secret_arn` / `aurora_sink_secret_arn` | Secrets Manager ARNs |
| `redis_endpoint` / `redis_port` | ElastiCache Redis endpoint |
| `s3_plugins_bucket` / `s3_data_lake_bucket` / `s3_logs_bucket` | S3 bucket names |
| `debezium_plugin_arn` / `debezium_connector_arn` | MSK Connect ARNs |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `BrokerUnreachable` on connector creation | MSK SG missing inbound 9098 from MSK Connect SG | Check `terraform apply -target=module.security_groups` succeeded |
| `ConnectorNotReady: 2 failed tasks` (sink) | Aurora Sink SG missing 5432 from MSK Connect SG | Re-apply security groups; verify rule via AWS console |
| `Aurora Limitless doesn't support engine modes` | AWS provider sends `engine_mode="provisioned"` even for Limitless | Module uses `null_resource` + AWS CLI to bypass — see [`aurora_source_limitless/main.tf`](./prod-stack/modules/aurora_source_limitless/main.tf) |
| `InvalidPermission.Duplicate` on SG apply | Rule was manually added in AWS console before Terraform | Either delete the manual rule, or remove it from Terraform code |
| `UNKNOWN_TOPIC_OR_PARTITION` from Kafka client | MSK broker config missing `auto.create.topics.enable=true` | Already set in `modules/msk/main.tf` — verify cluster has the custom config attached |
| `JsonConverter requires schema and payload` | Sink connector has `schemas.enable=true` but source produces schema-less JSON | Module is configured with `converter_schemas_enabled = false` to match source |
| Plan keeps wanting to delete an external resource | Resource was manually added or by another stack | `terraform state rm <addr>` to remove from state without touching AWS |
| `Error acquiring lock` | Another apply is in progress, or stale lock | Check the DynamoDB lock table; clear stale entries carefully |

---

**Maintained by:** Platform Team (panicleTech) · **For:** Caltech / TCS POC
