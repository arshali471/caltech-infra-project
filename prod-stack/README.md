# Caltech Production Stack — Terraform Deployment Guide

**Region:** us-west-2 | **Account:** caltect-account | **Stack:** `caltech-prod`

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                     AWS us-west-2  ·  Existing VPC                                   │
│                                                                                                      │
│  ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────────┐  │
│  │   PUBLIC SUBNET   │   │                   │   │                   │   │                       │  │
│  │                   │   │  PRIVATE SUBNET   │   │  PRIVATE SUBNET   │   │   PRIVATE SUBNET      │  │
│  │  ┌─────────────┐  │   │                   │   │                   │   │                       │  │
│  │  │  Amazon EC2 │──┼──▶│ RDS Aurora        │──▶│ MSK Connect       │──▶│ Consumer Apps         │  │
│  │  │             │  │   │ PostgreSQL DB     │   │ (Debezium / CDC)  │   │ Redis Sink            │──▶  ElastiCache Redis
│  │  │ Transaction │  │   │ (Source)          │   │                   │   │                       │  │
│  │  │ Simulator   │  │   │                   │   │         │         │   ├───────────────────────┤  │
│  │  └─────────────┘  │   │                   │   │         ▼         │   │                       │  │
│  │                   │   │                   │   │   MSK Serverless  │   │ Consumer Apps         │──▶  RDS Aurora
│  │                   │   │                   │   │   (Kafka)         │──▶│ PostgreSQL Sink       │     PostgreSQL DB
│  └───────────────────┘   └───────────────────┘   └───────────────────┘   └───────────────────────┘     (Sink)
└──────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow (Left → Right — matches the client diagram)

```
Amazon EC2              RDS Aurora          Consumer Apps       MSK              Consumer Apps          ElastiCache
(Transaction    ──────▶ PostgreSQL   ──────▶ Debezium /  ──────▶ Serverless ──┬─▶ Redis Sink    ──────▶ Redis
 Simulator)             DB (Source)          CDC                 (Kafka)       │
                                                                               └─▶ Consumer Apps  ──────▶ RDS Aurora
                                                                                   PostgreSQL Sink        PostgreSQL DB
                                                                                                          (Sink)
```

### Deployment Phases (Left → Right)

```
PHASE 1 — Foundation     PHASE 2      PHASE 3         PHASE 4                  PHASE 5
──────────────────────   ──────────   ─────────────   ─────────────────────    ──────────────────────────
kms                      ec2          aurora_source   msk (Kafka)              elasticache (Redis Sink)
security_groups    ────▶ (EC2 /  ────▶ (Source    ────▶ msk_connect         ────▶ aurora_sink (PG Sink)
s3                       App Server)   DB)              (Debezium CDC)
secrets
iam
```

---

## Quick Start — Run This First

```bash
cd prod-stack
chmod +x scripts/init.sh
./scripts/init.sh --profile caltect-account
```

The script reads `backend.hcl` automatically — creates S3 state bucket, DynamoDB lock table, runs `terraform init` and `terraform validate`.

---

## Prerequisites

| Requirement | Details |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | >= 2.x |
| AWS Profile | `caltect-account` configured in `~/.aws/credentials` |
| Existing VPC | Must already exist — get IDs from AWS console |
| EC2 AMI | Amazon Linux 2023 AMI ID for us-west-2 |
| Debezium ZIP | Downloaded and uploaded to S3 before MSK Connect step |

```bash
terraform version                                      # >= 1.5.0
aws --version                                          # >= 2.x
aws sts get-caller-identity --profile caltect-account  # verify auth
```

---

## Step 1 — Fill in Required Variables

Open `terraform.tfvars` and replace all `XXXXXXXXXXXXXXXXX` placeholders.

### Mandatory — must be set before any apply

| Variable | How to get it |
|---|---|
| `vpc_id` | `aws ec2 describe-vpcs --profile caltect-account --region us-west-2 --output table` |
| `public_subnet_ids` | Subnets where `MapPublicIpOnLaunch = true` |
| `private_subnet_ids` | Subnets where `MapPublicIpOnLaunch = false` |
| `ec2_ami_id` | See CLI command below |

**Get subnet IDs:**
```bash
aws ec2 describe-subnets \
  --profile caltect-account --region us-west-2 \
  --query "Subnets[*].{ID:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,Name:Tags[?Key=='Name']|[0].Value}" \
  --output table
```

**Get latest Amazon Linux 2023 AMI:**
```bash
aws ec2 describe-images \
  --profile caltect-account --region us-west-2 \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
  --query "sort_by(Images, &CreationDate)[-1].{ID:ImageId,Name:Name}" \
  --output table
```

### Version variables — adjust per client requirement

| Variable | Default | Change when |
|---|---|---|
| `aurora_engine_version` | `16.3` | Client specifies a different PostgreSQL version |
| `kafkaconnect_version` | `2.7.1` | Client requires a specific Kafka Connect version |
| `java_package` | `java-17-amazon-corretto` | Client needs Java 21 etc. |
| `msk_iam_auth_version` | `1.1.9` | New aws-msk-iam-auth release |
| `debezium_plugin_s3_key` | `plugins/debezium-connector-postgres-2.5.0.Final-plugin.zip` | Different Debezium version |

### Optional tuning — safe defaults, change only if needed

| Variable | Default | Description |
|---|---|---|
| `ec2_instance_type` | `t3.large` | EC2 instance size |
| `ec2_root_volume_gb` | `50` | Root disk size in GB |
| `aurora_source_min_acu` / `max_acu` | `0.5` / `16` | Aurora Source capacity range |
| `aurora_sink_min_acu` / `max_acu` | `0.5` / `16` | Aurora Sink capacity range |
| `aurora_backup_retention_period` | `7` | Days to keep automated backups |
| `aurora_deletion_protection` | `true` | Set `false` only for dev/test teardown |
| `aurora_skip_final_snapshot` | `false` | Set `true` for dev/test only |
| `redis_min_data_storage_gb` | `1` | ElastiCache minimum storage |
| `redis_max_data_storage_gb` | `100` | ElastiCache maximum storage |
| `msk_connect_min_workers` | `1` | Minimum Debezium worker count |
| `msk_connect_max_workers` | `2` | Maximum Debezium worker count |
| `debezium_snapshot_mode` | `initial` | `initial`, `never`, or `always` |
| `password_length` | `32` | Auto-generated Aurora password length |
| `kms_deletion_window_days` | `30` | KMS key deletion window (7–30) |

---

## Step 2 — Initialize Terraform

```bash
./scripts/init.sh --profile caltect-account
```

On success:
```
╔══════════════════════════════════╗
║      Bootstrap Complete!        ║
╚══════════════════════════════════╝
  State file : s3://caltech-terraform-state-<account-id>/caltech/prod/terraform.tfstate
  Lock table : caltech-terraform-lock (us-west-2)
```

---

## Step 3 — Sequential Deployment (Left → Right)

**Deploy each step in order. Verify success before moving to the next.**

---

## ── PHASE 1: Foundation ─────────────────────────────────────────────────────────

Shared infrastructure everything else depends on. No app-visible outputs yet.

---

### 3.1 — KMS Encryption Keys

```bash
terraform apply -target=module.kms
```

| Key alias | Used by |
|---|---|
| `alias/caltech-prod-ebs` | EC2 root volume |
| `alias/caltech-prod-s3` | S3 buckets |
| `alias/caltech-prod-aurora` | Both Aurora clusters |
| `alias/caltech-prod-redis` | ElastiCache |
| `alias/caltech-prod-secrets` | Secrets Manager |

**Verify:**
```bash
aws kms list-aliases --profile caltect-account --region us-west-2 \
  --query "Aliases[?contains(AliasName,'caltech')].AliasName" --output table
```

---

### 3.2 — Security Groups

```bash
terraform apply -target=module.security_groups
```

| Security Group | Inbound | Outbound |
|---|---|---|
| `caltech-prod-ec2-sg` | None (SSM only) | All |
| `caltech-prod-msk-sg` | 9098 from EC2 + MSK Connect SG | All |
| `caltech-prod-msk-connect-sg` | None | All |
| `caltech-prod-aurora-source-sg` | 5432 from EC2 + MSK Connect SG | All |
| `caltech-prod-aurora-sink-sg` | 5432 from EC2 SG | All |
| `caltech-prod-elasticache-sg` | 6379 from EC2 SG | All |

**Verify:**
```bash
aws ec2 describe-security-groups --profile caltect-account --region us-west-2 \
  --filters "Name=group-name,Values=caltech-prod-*" \
  --query "SecurityGroups[].GroupName" --output table
```

---

### 3.3 — S3 Buckets

```bash
terraform apply -target=module.s3
```

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `caltech-prod-msk-plugins` | Debezium connector ZIP | Versioned |
| `caltech-prod-data-lake` | Kafka consumer event archive | 30d→IA, 90d→Glacier |
| `caltech-prod-msk-logs` | MSK Connect worker logs | Expire after 90d |

**Verify:**
```bash
aws s3 ls --profile caltect-account | grep caltech
```

---

### 3.4 — Secrets Manager (Aurora Passwords)

```bash
terraform apply -target=module.secrets
```

Generates random 32-character passwords — **never stored in Terraform state**.

**Verify:**
```bash
aws secretsmanager list-secrets --profile caltect-account --region us-west-2 \
  --query "SecretList[?contains(Name,'caltech')].Name" --output table
```

---

### 3.5 — IAM Roles

> **Note:** IAM is deployed here with `msk_cluster_arn = "*"` (wildcard). After MSK Serverless is deployed in Phase 4, the final `terraform apply` automatically tightens the policy to the exact MSK cluster ARN.

```bash
terraform apply -target=module.iam
```

| Role | Trust | Permissions |
|---|---|---|
| `caltech-prod-ec2-app-role` | ec2.amazonaws.com | SSM · MSK SASL/IAM · Secrets read · S3 read/write |
| `caltech-prod-msk-connect-role` | kafkaconnect.amazonaws.com | MSK SASL/IAM · S3 plugin+logs · Secrets read · VPC networking |

**Verify:**
```bash
aws iam list-roles --profile caltect-account \
  --query "Roles[?contains(RoleName,'caltech')].RoleName" --output table
```

---

## ── PHASE 2: App Server (EC2 — leftmost in diagram) ───────────────────────────

### 3.6 — Amazon EC2 (Transaction Simulator)

```bash
terraform apply -target=module.ec2
```

**What gets created:**
- EC2 instance `caltech-prod-app-server` in public subnet
- SSM Session Manager access only (no SSH, no open ports)
- IMDSv2 enforced
- gp3 EBS root volume (KMS encrypted)
- Bootstrap installs: Java, AWS CLI, MSK IAM auth JAR

**Get instance ID and connect:**
```bash
terraform output ec2_instance_id

aws ssm start-session \
  --target $(terraform output -raw ec2_instance_id) \
  --region us-west-2 \
  --profile caltect-account
```

**Verify bootstrap (inside SSM session):**
```bash
java -version
ls -la /opt/aws-msk-iam-auth.jar
```

---

> ### 🚀 App Team Handoff — Phase 2
>
> | Item | Command |
> |---|---|
> | EC2 Instance ID | `terraform output ec2_instance_id` |
> | EC2 Public IP | `terraform output ec2_public_ip` |
> | SSM connect command | `terraform output ssm_connect_command` |
>
> App team can log into the EC2 instance and verify the Java runtime.

---

## ── PHASE 3: Source Database (Aurora PostgreSQL) ──────────────────────────────

### 3.7 — RDS Aurora PostgreSQL DB (Source)

> Takes 5–15 minutes to provision.

```bash
terraform apply -target=module.aurora_source
```

**What gets created:**
- Aurora Serverless v2 cluster `caltech-prod-aurora-source`
- Custom parameter group: `rds.logical_replication=1`, `max_replication_slots=10`, `max_wal_senders=10`
- KMS-encrypted storage · CloudWatch Logs export enabled

**Verify:**
```bash
aws rds describe-db-clusters --profile caltect-account --region us-west-2 \
  --db-cluster-identifier caltech-prod-aurora-source \
  --query "DBClusters[0].{Status:Status,Endpoint:Endpoint}" --output table
```

**Get connection details:**
```bash
terraform output aurora_source_endpoint

aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw aurora_source_secret_arn) \
  --query SecretString --output text \
  --profile caltect-account | python3 -m json.tool
```

---

> ### 🚀 App Team Handoff — Phase 3
>
> | Item | Value / Command |
> |---|---|
> | Source DB endpoint | `terraform output aurora_source_endpoint` |
> | Source DB port | `5432` |
> | Source DB name | `sourcedb` |
> | Source DB username | `dbadmin` |
> | Source DB password | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw aurora_source_secret_arn) --query SecretString --output text --profile caltect-account` |
>
> App team can now deploy and run the **Transaction Simulator** against Aurora Source.

---

## ── PHASE 4: CDC Pipeline (Debezium → MSK Connect → Kafka) ───────────────────

### 3.8 — MSK Serverless (Kafka)

> Takes 5–10 minutes to provision.

```bash
terraform apply -target=module.msk
```

**What gets created:**
- MSK Serverless cluster `caltech-prod-msk`
- SASL/IAM authentication · TLS in-transit · Multi-AZ across private subnets

**Verify:**
```bash
aws kafka list-clusters-v2 --profile caltect-account --region us-west-2 \
  --query "ClusterInfoList[?ClusterName=='caltech-prod-msk'].{Name:ClusterName,State:ClusterType}" \
  --output table
```

**Get broker endpoint:**
```bash
terraform output msk_bootstrap_brokers
```

---

### 3.9 — MSK Connect + Debezium CDC Connector

> **PREREQUISITE: Upload the Debezium ZIP to S3 before running terraform apply.**

#### 3.9a — Download Debezium connector ZIP

```bash
curl -L -o debezium-connector-postgres-2.5.0.Final-plugin.zip \
  "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.5.0.Final/debezium-connector-postgres-2.5.0.Final-plugin.zip"
```

#### 3.9b — Upload ZIP to the plugins S3 bucket

```bash
aws s3 cp debezium-connector-postgres-2.5.0.Final-plugin.zip \
  s3://$(terraform output -raw s3_plugins_bucket)/plugins/debezium-connector-postgres-2.5.0.Final-plugin.zip \
  --profile caltect-account

# Verify upload
aws s3 ls s3://$(terraform output -raw s3_plugins_bucket)/plugins/ --profile caltect-account
```

#### 3.9c — Deploy MSK Connect

> Takes 10–15 minutes to provision.

```bash
terraform apply -target=module.msk_connect
```

**What gets created:**
- Debezium PostgreSQL connector pointing at Aurora Source
- MSK Connect workers with autoscaling (1–2 workers, scale at 80% CPU)
- Log delivery to `caltech-prod-msk-logs` S3 bucket

**Verify connector is RUNNING:**
```bash
aws kafkaconnect list-connectors --profile caltect-account --region us-west-2 \
  --query "connectors[?connectorName=='caltech-prod-debezium-postgres-connector'].{Name:connectorName,State:connectorState}" \
  --output table
```

---

> ### 🚀 App Team Handoff — Phase 4
>
> CDC pipeline is live — changes written to Aurora Source now flow into Kafka topics:
>
> | Item | Command |
> |---|---|
> | MSK Bootstrap brokers | `terraform output msk_bootstrap_brokers` |
> | MSK Cluster ARN | `terraform output msk_cluster_arn` |
> | Kafka topic prefix | `caltech-prod.sourcedb.<table-name>` |
> | Connector status | `aws kafkaconnect list-connectors --profile caltect-account --region us-west-2` |
> | CDC logs | `aws s3 ls s3://$(terraform output -raw s3_logs_bucket)/msk-connect/ --profile caltect-account` |
>
> App team can verify CDC: write a row to Aurora Source → check the Kafka topic for the change event.

---

## ── PHASE 5: Consumer Targets (Right side of diagram) ─────────────────────────

### 3.10 — ElastiCache Redis Serverless (Redis Sink)

```bash
terraform apply -target=module.elasticache
```

**What gets created:**
- ElastiCache Serverless cache `caltech-prod-redis`
- TLS always-on · KMS-encrypted at rest

**Verify:**
```bash
aws elasticache describe-serverless-caches --profile caltect-account --region us-west-2 \
  --serverless-cache-name caltech-prod-redis \
  --query "ServerlessCaches[0].{Name:ServerlessCacheName,Status:Status,Endpoint:Endpoint.Address}" \
  --output table
```

```bash
terraform output redis_endpoint
terraform output redis_port
```

---

### 3.11 — RDS Aurora PostgreSQL DB (Sink)

> Takes 5–15 minutes to provision.

```bash
terraform apply -target=module.aurora_sink
```

**What gets created:**
- Aurora Serverless v2 cluster `caltech-prod-aurora-sink`
- KMS-encrypted storage · Deletion protection enabled

**Verify:**
```bash
aws rds describe-db-clusters --profile caltect-account --region us-west-2 \
  --db-cluster-identifier caltech-prod-aurora-sink \
  --query "DBClusters[0].{Status:Status,Endpoint:Endpoint}" --output table
```

```bash
terraform output aurora_sink_endpoint

aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw aurora_sink_secret_arn) \
  --query SecretString --output text \
  --profile caltect-account | python3 -m json.tool
```

---

> ### 🚀 App Team Handoff — Phase 5 (Full Stack Ready)
>
> Complete pipeline is deployed. Hand over all connection details:
>
> | Service | Item | Command |
> |---|---|---|
> | EC2 | Instance ID | `terraform output ec2_instance_id` |
> | EC2 | SSM connect | `terraform output ssm_connect_command` |
> | Aurora Source | Endpoint | `terraform output aurora_source_endpoint` |
> | Aurora Source | Password | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw aurora_source_secret_arn) --query SecretString --output text --profile caltect-account` |
> | MSK | Bootstrap brokers | `terraform output msk_bootstrap_brokers` |
> | Aurora Sink | Endpoint | `terraform output aurora_sink_endpoint` |
> | Aurora Sink | Password | `aws secretsmanager get-secret-value --secret-id $(terraform output -raw aurora_sink_secret_arn) --query SecretString --output text --profile caltect-account` |
> | Redis | Endpoint | `terraform output redis_endpoint` |
> | Redis | Port | `terraform output redis_port` |
> | S3 Data Lake | Bucket | `terraform output s3_data_lake_bucket` |
>
> **End-to-end test:**
> 1. Connect to EC2 via SSM
> 2. Run Transaction Simulator → writes rows to Aurora Source
> 3. Debezium captures changes → publishes to MSK Kafka topic
> 4. Redis Sink Consumer reads from MSK → writes to ElastiCache
> 5. PostgreSQL Sink Consumer reads from MSK → writes to Aurora Sink
> 6. Verify rows appear in both ElastiCache Redis and Aurora Sink DB

---

## ── PHASE 6: Final Pass ─────────────────────────────────────────────────────────

### 3.12 — Full Stack Apply

Tightens the IAM MSK policy from `*` to the exact MSK cluster ARN and confirms the full stack is consistent:

```bash
terraform apply
```

---

## Deployment Summary Table

| Phase | Step | Module | Command | Est. Time | App Team Gets |
|---|---|---|---|---|---|
| **Foundation** | 3.1 | kms | `terraform apply -target=module.kms` | 1 min | — |
| **Foundation** | 3.2 | security_groups | `terraform apply -target=module.security_groups` | 1 min | — |
| **Foundation** | 3.3 | s3 | `terraform apply -target=module.s3` | 1 min | — |
| **Foundation** | 3.4 | secrets | `terraform apply -target=module.secrets` | 1 min | — |
| **Foundation** | 3.5 | iam | `terraform apply -target=module.iam` | 1 min | — |
| **App Server** | 3.6 | ec2 | `terraform apply -target=module.ec2` | 2 min | ✅ SSM access |
| **Source DB** | 3.7 | aurora_source | `terraform apply -target=module.aurora_source` | 5–15 min | ✅ Source DB endpoint + password |
| **CDC** | 3.8 | msk | `terraform apply -target=module.msk` | 5–10 min | ✅ MSK broker endpoint |
| **CDC** | 3.9 | msk_connect | Upload ZIP → `terraform apply -target=module.msk_connect` | 10–15 min | ✅ Kafka topics live |
| **Consumers** | 3.10 | elasticache | `terraform apply -target=module.elasticache` | 2 min | ✅ Redis endpoint |
| **Consumers** | 3.11 | aurora_sink | `terraform apply -target=module.aurora_sink` | 5–15 min | ✅ Sink DB endpoint + password |
| **Final** | 3.12 | all | `terraform apply` | 1 min | ✅ Full stack + IAM tightened |

---

## All Outputs Reference

```bash
terraform output
```

| Output | Description |
|---|---|
| `ec2_instance_id` | EC2 instance ID |
| `ec2_public_ip` | EC2 public IP address |
| `ssm_connect_command` | Full `aws ssm start-session` command |
| `msk_cluster_arn` | MSK Serverless cluster ARN |
| `msk_bootstrap_brokers` | Kafka bootstrap broker string (SASL/IAM) |
| `aurora_source_endpoint` | Aurora Source writer endpoint |
| `aurora_source_reader_endpoint` | Aurora Source reader endpoint |
| `aurora_source_secret_arn` | Secrets Manager ARN for source password |
| `aurora_sink_endpoint` | Aurora Sink writer endpoint |
| `aurora_sink_reader_endpoint` | Aurora Sink reader endpoint |
| `aurora_sink_secret_arn` | Secrets Manager ARN for sink password |
| `redis_endpoint` | ElastiCache Redis endpoint |
| `redis_port` | ElastiCache Redis port (TLS) |
| `s3_plugins_bucket` | MSK plugin bucket name |
| `s3_data_lake_bucket` | Data lake bucket name |
| `s3_logs_bucket` | MSK logs bucket name |
| `debezium_plugin_arn` | Debezium custom plugin ARN |
| `debezium_connector_arn` | Debezium connector ARN |

---

## File Structure

```
prod-stack/
├── main.tf                  # Root orchestrator — calls all 11 modules
├── variables.tf             # All input variables with descriptions and defaults
├── outputs.tf               # All stack outputs
├── data.tf                  # AWS account identity + VPC data sources
├── versions.tf              # Provider version constraints
├── providers.tf             # AWS provider + default_tags
├── backend.tf               # Remote state backend config
├── backend.hcl              # Backend values (bucket, key, region, profile)
├── terraform.tfvars         # ← EDIT THIS FILE before deploying
│
└── modules/
    ├── kms/                 # Step 3.1 — 5 KMS CMKs (ebs, s3, aurora, redis, secrets)
    ├── security_groups/     # Step 3.2 — 6 security groups (one per service)
    ├── s3/                  # Step 3.3 — 3 S3 buckets (plugins, data-lake, logs)
    ├── secrets/             # Step 3.4 — Secrets Manager (Aurora passwords)
    ├── iam/                 # Step 3.5 — EC2 + MSK Connect IAM roles
    ├── ec2/                 # Step 3.6 — App server / Transaction Simulator
    ├── aurora_source/       # Step 3.7 — Aurora Source DB (logical replication ON)
    ├── msk/                 # Step 3.8 — MSK Serverless (Kafka)
    ├── msk_connect/         # Step 3.9 — Debezium CDC connector on MSK Connect
    ├── elasticache/         # Step 3.10 — ElastiCache Redis Serverless
    └── aurora_sink/         # Step 3.11 — Aurora Sink DB (PostgreSQL consumer)
```

---

## Updating a Single Service

```bash
# Resize EC2
terraform apply -target=module.ec2

# Upgrade Aurora engine version (update aurora_engine_version in tfvars first)
terraform apply -target=module.aurora_source
terraform apply -target=module.aurora_sink

# Upgrade Debezium (upload new ZIP to S3, update debezium_plugin_s3_key in tfvars)
terraform apply -target=module.msk_connect

# Resize Redis (update redis_max_ecpu_per_second in tfvars)
terraform apply -target=module.elasticache
```

---

## Deploying for a Different Client / Environment

```bash
cp terraform.tfvars terraform-staging.tfvars
# Edit: aws_profile, environment, project, vpc_id, subnets, versions
terraform apply -var-file=terraform-staging.tfvars
```

---

## Destroying the Stack

> **Warning:** Destroys all data. Disable Aurora deletion protection first.

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

## Common Issues

| Issue | Cause | Fix |
|---|---|---|
| `ResourceNotFoundException` on DynamoDB lock | Wrong AWS profile | Ensure `profile = "caltect-account"` in `backend.hcl`, re-run `terraform init -backend-config=backend.hcl -reconfigure` |
| `BucketAlreadyExists` on state bucket | Name taken by another account | Add account ID: `caltech-terraform-state-<account-id>` in `backend.hcl` |
| `SubscriptionRequiredException` on MSK | Account not activated | Accept MSK Serverless terms in AWS console |
| MSK Connect `plugin not found` | Debezium ZIP not in S3 | Complete Step 3.9a–b before 3.9c |
| Aurora creation timeout | Normal — takes 5–15 min | Wait, then rerun `terraform apply -target=module.aurora_source` |
| `Secret already exists` | Recovery window active | Set `secret_recovery_window_days = 0` and reapply |
| `Error acquiring state lock` | Previous run crashed | Run `terraform force-unlock <lock-id>` |
| EC2 bootstrap failed | user_data error | Check `/var/log/cloud-init-output.log` via SSM session |

---

## Security Notes

- **No SSH ports** — EC2 access via SSM Session Manager only
- **IMDSv2 enforced** — prevents SSRF-based credential theft on EC2
- **TLS everywhere** — MSK in-transit, ElastiCache always-on TLS, S3 TLS-only policy
- **KMS CMK per service** — separate key per service; compromise of one does not expose others
- **Account-only S3 policy** — buckets deny all requests from other AWS accounts
- **Secrets Manager** — passwords never in Terraform state; `lifecycle { ignore_changes = [master_password] }` on all Aurora clusters
- **Deletion protection** — Aurora clusters default to `deletion_protection = true`
- **IAM least-privilege** — MSK policy tightened to exact cluster ARN on final `terraform apply`
