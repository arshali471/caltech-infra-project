# Caltech POC Stack — Terraform Deployment Guide

**Region:** us-west-2 | **Account:** 342448511503 | **Profile:** `default` | **Stack:** `caltech-poc`

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS us-west-2  ·  VPC vpc-0ed44b92f11b73815                               │
│                                                                                                        │
│  ┌─────────────────────┐   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────────┐  │
│  │   PUBLIC SUBNET     │   │                   │   │                   │   │                       │  │
│  │                     │   │  PRIVATE SUBNET   │   │  PRIVATE SUBNET   │   │   PRIVATE SUBNET      │  │
│  │  ┌───────────────┐  │   │                   │   │                   │   │                       │  │
│  │  │  Amazon EC2   │──┼──▶│ Aurora PostgreSQL │──▶│ MSK Connect       │──▶│ Redis Sink            │──▶ ElastiCache
│  │  │  t3.xlarge    │  │   │ Source DB (17.7)  │   │ (Debezium / CDC)  │   │                       │  │
│  │  │  no public IP │  │   │                   │   │         ▼         │   ├───────────────────────┤  │
│  │  │  jump server  │  │   │                   │   │ MSK Provisioned   │   │                       │  │
│  │  │  SSH access   │  │   │                   │   │ Kafka 3.9.0       │──▶│ PostgreSQL Sink        │──▶ Aurora Sink
│  │  └───────────────┘  │   │                   │   │ kafka.m5.2xlarge  │   │                       │  │
│  │  VPC Endpoints      │   │                   │   │ 2 Brokers         │   │                       │  │
│  │  (SSM/SSMMsg/EC2Msg)│   │                   │   │ SASL/SCRAM + IAM  │   │                       │  │
│  └─────────────────────┘   └───────────────────┘   └───────────────────┘   └───────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow (Left to Right)

```
Amazon EC2           Aurora PostgreSQL    Debezium CDC        MSK Provisioned    Consumer Targets
(Transaction  ──────▶ Source DB    ──────▶ (MSK Connect) ──────▶ Kafka 3.9.0 ──┬──▶ ElastiCache Redis
 Simulator)           (17.7)                                    2 Brokers        │
                                                                SASL/SCRAM       └──▶ Aurora PostgreSQL
                                                                                        Sink DB (17.7)
```

### Deployment Phases (Left to Right)

```
PHASE 1 — Foundation          PHASE 2         PHASE 3          PHASE 4                 PHASE 5
─────────────────────────     ───────────────  ──────────────   ──────────────────────   ─────────────────────────
kms                           ec2              aurora_source    msk (Kafka)              elasticache (Redis Sink)
security_groups    ─────────▶ vpc_endpoints ──▶ (Source DB) ────▶ msk_connect         ──▶ aurora_sink (PG Sink)
s3                            (App Server)                        (Debezium CDC)
secrets
iam
```

---

## Current Configuration

| Setting | Value |
|---|---|
| Environment | `poc` |
| VPC | `vpc-0ed44b92f11b73815` |
| Public Subnets | `subnet-038946a978f266b7d`, `subnet-052b8a9527604c064` |
| Private Subnets | `subnet-0afa40d43201113c7`, `subnet-09fbbd79068ad5555` |
| EC2 AMI | `ami-04486bbfa25728941` |
| EC2 Type | `t3.xlarge` · 100 GB gp3 · no public IP |
| EC2 Access | Jump server SSH (port 22, VPC CIDR only) + SSM via VPC endpoints |
| EC2 Key Pair | `caltech-keypair` |
| SSH Allowed CIDR | `172.31.0.0/16` (VPC only) |
| Aurora Version | `17.7` |
| MSK Type | Provisioned · Kafka 3.9.0 · `kafka.m5.2xlarge` |
| MSK Brokers | 2 (one per private subnet/AZ) |
| MSK Auth | SASL/SCRAM port 9096 (app clients) + IAM port 9098 (MSK Connect) |
| MSK Storage | 250 GB per broker |
| State Bucket | `caltech-terraform-state-342448511503` |

---

## Quick Start

```bash
cd prod-stack
chmod +x scripts/init.sh
./scripts/init.sh --profile default
```

Creates S3 state bucket, DynamoDB lock table, runs `terraform init` and `terraform validate`.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x |
| AWS Profile | `default` configured in `~/.aws/credentials` |
| EC2 Key Pair | `caltech-keypair` created in AWS console (us-west-2) |
| Jump Server | Required for SSH to EC2 — EC2 has no public IP |
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

## PHASE 1: Foundation

### 3.1 — KMS Encryption Keys

```bash
terraform apply -target=module.kms
```

| Key alias | Used by |
|---|---|
| `alias/caltech-poc-ebs` | EC2 root volume |
| `alias/caltech-poc-s3` | S3 buckets |
| `alias/caltech-poc-aurora` | Both Aurora clusters |
| `alias/caltech-poc-redis` | ElastiCache |
| `alias/caltech-poc-secrets` | Secrets Manager + MSK SCRAM secret |

**Verify:**
```bash
aws kms list-aliases --profile default --region us-west-2 \
  --query "Aliases[?contains(AliasName,'caltech')].AliasName" --output table
```

---

### 3.2 — Security Groups

```bash
terraform apply -target=module.security_groups
```

| Security Group | Inbound | Outbound |
|---|---|---|
| `caltech-poc-ec2-sg` | SSH 22 from `172.31.0.0/16` | All |
| `caltech-poc-vpce-sg` | HTTPS 443 from EC2 SG | All |
| `caltech-poc-msk-sg` | 9098 IAM + 9096 SCRAM from EC2 + MSK Connect | All |
| `caltech-poc-msk-connect-sg` | None | All |
| `caltech-poc-aurora-source-sg` | 5432 from EC2 + MSK Connect | All |
| `caltech-poc-aurora-sink-sg` | 5432 from EC2 | All |
| `caltech-poc-elasticache-sg` | 6379 from EC2 | All |

**Verify:**
```bash
aws ec2 describe-security-groups --profile default --region us-west-2 \
  --filters "Name=group-name,Values=caltech-poc-*" \
  --query "SecurityGroups[].GroupName" --output table
```

---

### 3.2b — VPC Endpoints (SSM)

> Required — EC2 has no public IP so SSM agent cannot reach AWS endpoints over the internet.

```bash
terraform apply -target=module.vpc_endpoints
```

Creates 3 interface endpoints in the public subnets: `ssm`, `ssmmessages`, `ec2messages`.
SSM Session Manager will show green after ~2 minutes.

**Verify:**
```bash
aws ec2 describe-vpc-endpoints --profile default --region us-west-2 \
  --filters "Name=tag:Name,Values=caltech-poc-vpce-*" \
  --query "VpcEndpoints[*].{Name:Tags[?Key=='Name']|[0].Value,State:State}" --output table
```

---

### 3.3 — S3 Buckets

> `PutPublicAccessBlock` and `PutBucketPolicy` are skipped — enforced by the org SCP at account level.

```bash
terraform apply -target=module.s3
```

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `caltech-poc-msk-plugins` | Debezium connector ZIP | Versioned, KMS encrypted |
| `caltech-poc-data-lake` | Kafka consumer event archive | 30d to IA, 90d to Glacier |
| `caltech-poc-msk-logs` | MSK Connect worker logs | Expire after 90d |

**Verify:**
```bash
aws s3 ls --profile default | grep caltech
```

---

### 3.4 — Secrets Manager (Aurora Passwords)

```bash
terraform apply -target=module.secrets
```

Generates random 32-character passwords — never stored in Terraform state.

**Verify:**
```bash
aws secretsmanager list-secrets --profile default --region us-west-2 \
  --query "SecretList[?contains(Name,'caltech')].Name" --output table
```

---

### 3.5 — IAM Roles

```bash
terraform apply -target=module.iam
```

| Role | Trust | Permissions |
|---|---|---|
| `caltech-poc-ec2-app-role` | ec2.amazonaws.com | SSM · MSK SASL/IAM · Secrets read · S3 read/write |
| `caltech-poc-msk-connect-role` | kafkaconnect.amazonaws.com | MSK SASL/IAM · S3 plugin+logs · Secrets read · VPC |

**Verify:**
```bash
aws iam list-roles --profile default \
  --query "Roles[?contains(RoleName,'caltech')].RoleName" --output table
```

---

## PHASE 2: App Server

### 3.6 — Amazon EC2 (Transaction Simulator)

```bash
terraform apply -target=module.ec2
```

**What gets created:**
- EC2 `caltech-poc-app-server` · `t3.xlarge` · 100 GB gp3 (KMS encrypted)
- Public subnet, **no public IP** — SSH via jump server, SSM via VPC endpoints
- Key pair `caltech-keypair` · IMDSv2 enforced

**Connect via SSM:**
```bash
aws ssm start-session \
  --target $(terraform output -raw ec2_instance_id) \
  --region us-west-2 --profile default
```

**Connect via jump server SSH:**
```bash
ssh -J ec2-user@<jump-server-public-ip> \
    -i caltech-keypair.pem \
    ec2-user@$(terraform output -raw ec2_private_ip)
```

---

> ### App Team Handoff — Phase 2
>
> | Item | Command |
> |---|---|
> | EC2 Instance ID | `terraform output ec2_instance_id` |
> | EC2 Private IP | `terraform output ec2_private_ip` |
> | SSM connect | `aws ssm start-session --target $(terraform output -raw ec2_instance_id) --region us-west-2 --profile default` |

---

## PHASE 3: Source Database

### 3.7 — Aurora PostgreSQL Source DB

> Takes 5–15 minutes to provision.

```bash
terraform apply -target=module.aurora_source
```

**What gets created:**
- Aurora Serverless v2 `caltech-poc-aurora-source` · PostgreSQL 17.7
- Logical replication: `rds.logical_replication=1`, `max_replication_slots=10`, `max_wal_senders=10`
- KMS encrypted · CloudWatch Logs · Deletion protection ON

**Verify:**
```bash
aws rds describe-db-clusters --profile default --region us-west-2 \
  --db-cluster-identifier caltech-poc-aurora-source \
  --query "DBClusters[0].{Status:Status,Endpoint:Endpoint}" --output table
```

**Get password:**
```bash
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw aurora_source_secret_arn) \
  --query SecretString --output text --profile default
```

---

> ### App Team Handoff — Phase 3
>
> | Item | Value |
> |---|---|
> | Source DB endpoint | `terraform output aurora_source_endpoint` |
> | Port | `5432` |
> | DB name | `sourcedb` |
> | Username | `dbadmin` |
> | Password | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw aurora_source_secret_arn) --query SecretString --output text --profile default` |

---

## PHASE 4: CDC Pipeline

### 3.8 — MSK Provisioned (Kafka)

> Takes 15–30 minutes to provision.

```bash
terraform apply -target=module.msk
```

**What gets created:**
- MSK Provisioned `caltech-poc-msk` · Kafka 3.9.0 · KRaft mode
- `kafka.m5.2xlarge` · 2 brokers · 250 GB EBS each
- SASL/SCRAM port 9096 (app clients) + IAM port 9098 (MSK Connect)
- SCRAM credentials stored in Secrets Manager: `AmazonMSK_caltech-poc-scram` · username: `kafkauser`

**Verify:**
```bash
aws kafka list-clusters-v2 --profile default --region us-west-2 \
  --query "ClusterInfoList[?ClusterName=='caltech-poc-msk'].{Name:ClusterName,State:ClusterType}" \
  --output table
```

**Get broker endpoints:**
```bash
terraform output msk_bootstrap_brokers      # SASL/SCRAM port 9096 — for app clients
terraform output msk_bootstrap_brokers_iam  # IAM port 9098 — for MSK Connect
```

**Get SCRAM password:**
```bash
aws secretsmanager get-secret-value \
  --secret-id AmazonMSK_caltech-poc-scram \
  --query SecretString --output text --profile default
```

---

### 3.9 — MSK Connect + Debezium CDC

> Upload the Debezium ZIP to S3 before running terraform apply.

#### 3.9a — Download Debezium ZIP

```bash
curl -L -o debezium-connector-postgres-2.5.0.Final-plugin.zip \
  "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.0.Final/debezium-connector-postgres-2.5.0.Final-plugin.zip"
```

#### 3.9b — Upload to S3

```bash
aws s3 cp debezium-connector-postgres-2.5.0.Final-plugin.zip \
  s3://$(terraform output -raw s3_plugins_bucket)/plugins/debezium-connector-postgres-2.5.0.Final-plugin.zip \
  --profile default

aws s3 ls s3://$(terraform output -raw s3_plugins_bucket)/plugins/ --profile default
```

#### 3.9c — Deploy MSK Connect

> Takes 10–15 minutes.

```bash
terraform apply -target=module.msk_connect
```

MSK Connect workers authenticate to MSK via **IAM** (port 9098). Autoscaling 1–2 workers, scale at 80% CPU.

**Verify connector RUNNING:**
```bash
aws kafkaconnect list-connectors --profile default --region us-west-2 \
  --query "connectors[?connectorName=='caltech-poc-debezium-postgres-connector'].{Name:connectorName,State:connectorState}" \
  --output table
```

---

> ### App Team Handoff — Phase 4
>
> | Item | Command |
> |---|---|
> | MSK brokers (SASL/SCRAM) | `terraform output msk_bootstrap_brokers` |
> | MSK Cluster ARN | `terraform output msk_cluster_arn` |
> | SCRAM username | `kafkauser` |
> | SCRAM password | `aws secretsmanager get-secret-value --secret-id AmazonMSK_caltech-poc-scram --query SecretString --output text --profile default` |
> | Kafka topic prefix | `caltech-poc.sourcedb.<table-name>` |

---

## PHASE 5: Consumer Targets

### 3.10 — ElastiCache Redis Serverless

```bash
terraform apply -target=module.elasticache
```

Creates `caltech-poc-redis` · TLS always-on · KMS encrypted.

```bash
terraform output redis_endpoint
terraform output redis_port
```

---

### 3.11 — Aurora PostgreSQL Sink DB

> Takes 5–15 minutes.

```bash
terraform apply -target=module.aurora_sink
```

Creates `caltech-poc-aurora-sink` · PostgreSQL 17.7 · KMS encrypted · Deletion protection ON.

```bash
terraform output aurora_sink_endpoint

aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw aurora_sink_secret_arn) \
  --query SecretString --output text --profile default
```

---

> ### App Team Handoff — Phase 5 (Full Stack Ready)
>
> | Service | Item | Command |
> |---|---|---|
> | EC2 | Private IP | `terraform output ec2_private_ip` |
> | EC2 | SSM | `aws ssm start-session --target $(terraform output -raw ec2_instance_id) --region us-west-2 --profile default` |
> | Aurora Source | Endpoint | `terraform output aurora_source_endpoint` |
> | Aurora Source | Password | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw aurora_source_secret_arn) --query SecretString --output text --profile default` |
> | MSK | SCRAM brokers | `terraform output msk_bootstrap_brokers` |
> | MSK | SCRAM password | `aws secretsmanager get-secret-value --secret-id AmazonMSK_caltech-poc-scram --query SecretString --output text --profile default` |
> | Aurora Sink | Endpoint | `terraform output aurora_sink_endpoint` |
> | Aurora Sink | Password | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw aurora_sink_secret_arn) --query SecretString --output text --profile default` |
> | Redis | Endpoint | `terraform output redis_endpoint` |

---

## PHASE 6: Final Pass

```bash
terraform apply
```

Tightens IAM MSK policy from `*` to the exact cluster ARN. Validates full stack consistency.

---

## Deployment Summary Table

| Phase | Step | Module | Command | Est. Time | App Team Gets |
|---|---|---|---|---|---|
| Foundation | 3.1 | kms | `terraform apply -target=module.kms` | 1 min | — |
| Foundation | 3.2 | security_groups | `terraform apply -target=module.security_groups` | 1 min | — |
| Foundation | 3.2b | vpc_endpoints | `terraform apply -target=module.vpc_endpoints` | 2 min | — |
| Foundation | 3.3 | s3 | `terraform apply -target=module.s3` | 1 min | — |
| Foundation | 3.4 | secrets | `terraform apply -target=module.secrets` | 1 min | — |
| Foundation | 3.5 | iam | `terraform apply -target=module.iam` | 1 min | — |
| App Server | 3.6 | ec2 | `terraform apply -target=module.ec2` | 2 min | Instance ID + private IP |
| Source DB | 3.7 | aurora_source | `terraform apply -target=module.aurora_source` | 5–15 min | Source DB endpoint + password |
| CDC | 3.8 | msk | `terraform apply -target=module.msk` | 15–30 min | MSK brokers + SCRAM credentials |
| CDC | 3.9 | msk_connect | Upload ZIP then `terraform apply -target=module.msk_connect` | 10–15 min | Kafka topics live |
| Consumers | 3.10 | elasticache | `terraform apply -target=module.elasticache` | 2 min | Redis endpoint |
| Consumers | 3.11 | aurora_sink | `terraform apply -target=module.aurora_sink` | 5–15 min | Sink DB endpoint + password |
| Final | 3.12 | all | `terraform apply` | 1 min | Full stack + IAM tightened |

---

## File Structure

```
prod-stack/
├── main.tf                  # Root orchestrator — calls all 12 modules
├── variables.tf             # All input variables with descriptions and defaults
├── outputs.tf               # All stack outputs
├── data.tf                  # AWS account identity data source
├── versions.tf              # Provider version constraints
├── providers.tf             # AWS provider + default_tags
├── backend.hcl              # bucket=caltech-terraform-state-342448511503, profile=default
├── terraform.tfvars         # Active config — all real IDs filled in
├── scripts/
│   └── init.sh              # Bootstrap script (Windows MINGW64 + Linux compatible)
│
└── modules/
    ├── kms/                 # Step 3.1 — 5 KMS CMKs (ebs, s3, aurora, redis, secrets)
    ├── security_groups/     # Step 3.2 — 7 SGs (SSH on EC2, dual MSK ports 9096+9098)
    ├── vpc_endpoints/       # Step 3.2b — SSM interface endpoints (ssm, ssmmessages, ec2messages)
    ├── s3/                  # Step 3.3 — 3 S3 buckets (no public-access-block, org SCP enforces)
    ├── secrets/             # Step 3.4 — Secrets Manager (Aurora passwords)
    ├── iam/                 # Step 3.5 — EC2 + MSK Connect IAM roles
    ├── ec2/                 # Step 3.6 — t3.xlarge, no public IP, caltech-keypair
    ├── aurora_source/       # Step 3.7 — Aurora Source 17.7 (logical replication ON)
    ├── msk/                 # Step 3.8 — MSK Provisioned Kafka 3.9.0, SASL/SCRAM+IAM, 250GB
    ├── msk_connect/         # Step 3.9 — Debezium CDC connector (IAM auth to MSK)
    ├── elasticache/         # Step 3.10 — ElastiCache Redis Serverless
    └── aurora_sink/         # Step 3.11 — Aurora Sink 17.7
```

---

## MSK Broker Count

Currently **2 brokers** (2 private subnets). Client requirement is 3. To upgrade:

1. Create a 3rd private subnet in a 3rd AZ (`us-west-2c`) in the AWS console
2. Update `terraform.tfvars`:
   ```hcl
   private_subnet_ids = ["subnet-0afa40d43201113c7", "subnet-09fbbd79068ad5555", "subnet-NEW-ID"]
   msk_broker_count   = 3
   ```
3. `terraform apply -target=module.msk`

---

## Common Issues

| Issue | Cause | Fix |
|---|---|---|
| `AccessDenied PutPublicAccessBlock` | Org SCP — expected | Script warns and continues. Buckets are private via org policy |
| `AccessDenied PutBucketPolicy` | Org SCP — expected | Removed from S3 module. Org policy enforces account isolation |
| SSM agent offline | No public IP + VPC endpoints not deployed | Deploy `module.vpc_endpoints` then wait 2 min |
| `BucketAlreadyExists` | Bucket name taken by another account | Script suggests `caltech-terraform-state-<account-id>` |
| MSK `Invalid kafka version` | Kafka 3.9.0 not available yet | `aws kafka list-kafka-versions --region us-west-2` — use latest 3.x |
| MSK Connect `plugin not found` | Debezium ZIP not uploaded | Complete step 3.9a and 3.9b before 3.9c |
| Aurora timeout | Normal — takes 5–15 min | Wait, then rerun `terraform apply -target=module.aurora_source` |
| `Secret already exists` | Recovery window active | Set `secret_recovery_window_days = 0` and reapply |
| `Error acquiring state lock` | Previous run crashed | `terraform force-unlock <lock-id>` |

---

## Destroying the Stack

```bash
# Step 1 — Disable deletion protection
terraform apply \
  -target=module.aurora_source \
  -target=module.aurora_sink \
  -var="aurora_deletion_protection=false" \
  -var="aurora_skip_final_snapshot=true"

# Step 2 — Destroy MSK Connect first (depends on MSK, S3, IAM)
terraform destroy -target=module.msk_connect

# Step 3 — Destroy everything else
terraform destroy
```

---

## Security Notes

- **No public IP on EC2** — accessible only via jump server SSH (`172.31.0.0/16`) or SSM
- **SSM via VPC endpoints** — SSM traffic stays on AWS private network
- **IMDSv2 enforced** — prevents SSRF-based credential theft on EC2
- **MSK dual auth** — SASL/SCRAM (port 9096) for app clients, IAM (port 9098) for MSK Connect
- **SCRAM credentials** — auto-generated in Secrets Manager as `AmazonMSK_caltech-poc-scram`
- **KMS CMK per service** — ebs, s3, aurora, redis, secrets each have their own key
- **Org SCP enforced** — public access block and bucket policies managed at org level, not per-bucket
- **Deletion protection** — Aurora clusters default to `deletion_protection = true`
- **IAM least-privilege** — MSK policy tightened to exact cluster ARN on final `terraform apply`
