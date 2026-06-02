# Caltech POC — Full Stack Documentation

> **Audience:** Platform engineers, app team integrators, on-call operators
> **Scope:** End-to-end operational reference for the `prod-stack` Terraform project
> **Companion to:** [`README.md`](./README.md) (quick deployment guide)

### What's currently deployed

| Service | Count / Configuration |
|---|---|
| **EC2 app servers** | **3** instances — `caltech-poc-app-server` on **`m6i.2xlarge`** (8 vCPU, 32 GiB); `caltech-poc-pg-sink-app-server` + `caltech-poc-redis-sink-app-server` on `t3.xlarge` (4 vCPU, 16 GiB); all KMS-encrypted EBS |
| **Aurora PostgreSQL Source** | 1 cluster (Serverless v2, 0.5–16 ACUs) with logical replication |
| **Aurora PostgreSQL Source Limitless** | 1 cluster + 1 shard group (`16.13-limitless`, 16–32 ACUs, sharded) |
| **Aurora PostgreSQL Sink** | 1 cluster (Serverless v2, 0.5–16 ACUs) |
| **MSK Provisioned Kafka** | **3 brokers** across 3 AZs (`kafka.m5.2xlarge`, 1000 GB EBS each, Kafka 3.9.x) |
| **MSK Connect** | 6 connectors — 1 Debezium source + 5 JDBC sinks |
| **ElastiCache Redis** | Serverless cache (TLS always-on, KMS encrypted) |

---

## Table of Contents

1. [Stack Summary](#1-stack-summary)
2. [Module Reference](#2-module-reference)
3. [Network & Subnet Layout](#3-network--subnet-layout)
4. [Security Group Matrix](#4-security-group-matrix)
5. [IAM Roles & Trust Relationships](#5-iam-roles--trust-relationships)
6. [Encryption Strategy](#6-encryption-strategy)
7. [Aurora Source vs Sink vs Limitless](#7-aurora-source-vs-sink-vs-limitless)
8. [MSK Provisioned Cluster](#8-msk-provisioned-cluster)
9. [MSK Connect — Source & Sink Connectors](#9-msk-connect--source--sink-connectors)
10. [ElastiCache Redis](#10-elasticache-redis)
11. [EC2 App Servers](#11-ec2-app-servers)
12. [State Management](#12-state-management)
13. [Operations Runbook](#13-operations-runbook)
14. [Disaster Recovery & Backups](#14-disaster-recovery--backups)
15. [Known Issues & Workarounds](#15-known-issues--workarounds)
16. [Cost Notes](#16-cost-notes)
17. [Change Log](#17-change-log)

---

## 1. Stack Summary

| Item | Value |
|---|---|
| **Stack name** | `caltech-poc` |
| **AWS Account** | `342448511503` |
| **Region** | `us-west-2` |
| **Environment** | `poc` |
| **Owner** | `platform-team` |
| **Cost Center** | `engineering` |
| **Project** | `caltech` |
| **Terraform version** | ≥ 1.5.0 |
| **AWS provider** | ≥ 5.95.0, < 6.0.0 |
| **Random provider** | ~> 3.0 |
| **Null provider** | ~> 3.0 |
| **State backend** | S3 (`caltech-terraform-state-342448511503`) + DynamoDB lock |

**Default tags applied to every resource** (via provider `default_tags`):

```
Environment = poc
Project     = caltech
ManagedBy   = terraform
Owner       = platform-team
CostCenter  = engineering
Terraform   = true
```

---

## 2. Module Reference

### 2.1 `kms`

Creates 5 customer-managed KMS keys with aliases, each scoped to one AWS service. Key rotation is enabled by default.

| Output | Use |
|---|---|
| `ebs_key_arn` | EC2 root volume encryption |
| `s3_key_arn` | S3 bucket SSE-KMS |
| `aurora_key_arn` | Aurora storage encryption (all 3 clusters) |
| `redis_key_arn` | ElastiCache encryption at rest |
| `secrets_key_arn` | Secrets Manager + MSK SCRAM encryption |

**Variables:** `name`, `deletion_window_days` (default 7), `tags`

### 2.2 `security_groups`

Creates one security group per service with explicit ingress rules. Egress is `all → 0.0.0.0/0` for every SG. All SGs use `lifecycle { create_before_destroy = true }` to avoid in-place dependency conflicts.

| SG | Ingress |
|---|---|
| `caltech-poc-ec2-sg` | SSH 22 from VM CIDR; App 8080 from VM CIDR |
| `caltech-poc-msk-sg` | 9098 from EC2+MSKConnect (IAM); 9096 from EC2+MSKConnect (SCRAM); 9092 from MSKConnect; 9094 from MSKConnect |
| `caltech-poc-msk-connect-sg` | (none — outbound only) |
| `caltech-poc-aurora-source-sg` | 5432 from EC2 + MSKConnect + VM CIDR |
| `caltech-poc-aurora-sink-sg` | 5432 from EC2 + MSKConnect + VM CIDR |
| `caltech-poc-elasticache-sg` | 6379 from EC2 + VM CIDR |

**Variables:** `name`, `vpc_id`, `msk_port` (9098), `msk_scram_port` (9096), `postgres_port` (5432), `redis_port` (6379), `ssh_allowed_cidr`, `tags`

### 2.3 `vpc_endpoints`

Creates SSM interface endpoints and an S3 Gateway endpoint to allow EC2 instances without public IPs to use Systems Manager and access S3.

| Endpoint | Type | Service |
|---|---|---|
| `caltech-poc-vpce-ssm` | Interface | `com.amazonaws.us-west-2.ssm` |
| `caltech-poc-vpce-ssmmessages` | Interface | `com.amazonaws.us-west-2.ssmmessages` |
| `caltech-poc-vpce-ec2messages` | Interface | `com.amazonaws.us-west-2.ec2messages` |
| `caltech-poc-vpce-s3` | Gateway | `com.amazonaws.us-west-2.s3` (public route tables) |

> STS, SecretsManager, and a private-subnet S3 Gateway endpoint already exist in the VPC and are managed outside this stack — do not recreate them.

**Variables:** `name`, `vpc_id`, `aws_region`, `subnet_ids` (public), `public_route_table_ids`, `tags`

### 2.4 `s3`

Creates 3 buckets with KMS encryption, versioning, and lifecycle rules. `PutPublicAccessBlock` and `PutBucketPolicy` are intentionally NOT called — the org SCP enforces those at the account level.

| Bucket | Purpose | Lifecycle |
|---|---|---|
| `caltech-poc-msk-plugins` | Debezium + JDBC sink connector ZIPs | Versioned forever |
| `caltech-poc-data-lake` | Long-term Kafka event archive | `data_lake_ia_transition_days` → IA; `data_lake_glacier_transition_days` → Glacier |
| `caltech-poc-msk-logs` | MSK Connect worker CloudWatch logs (optional archive) | Expire after `logs_expiry_days` |

### 2.5 `secrets`

Auto-generates 32-character random passwords and stores them in AWS Secrets Manager. Passwords are never written to Terraform state in plain text (Terraform stores them encrypted in state, but they're treated as sensitive).

| Secret | Username |
|---|---|
| `caltech-poc-aurora-source-password` | `dbadmin` |
| `caltech-poc-aurora-sink-password` | `dbadmin` |

The MSK SCRAM secret is created separately by the `msk` module as `AmazonMSK_caltech-poc-scram` with username `kafkauser`.

### 2.6 `iam`

Creates two service roles:

#### `caltech-poc-ec2-app-role`
- **Trust:** `ec2.amazonaws.com`
- **Policies:** `AmazonSSMManagedInstanceCore`, plus inline policies for:
  - MSK SASL/IAM (`kafka-cluster:Connect`, `kafka-cluster:DescribeCluster`, `kafka-cluster:ReadData`, `kafka-cluster:WriteData` scoped to the cluster ARN)
  - SecretsManager read on Aurora secrets
  - S3 read/write on data-lake and plugins buckets

#### `caltech-poc-msk-connect-role`
- **Trust:** `kafkaconnect.amazonaws.com`
- **Policies:**
  - MSK SASL/IAM (scoped to cluster ARN, topic ARN `topic/caltech-poc-msk/*`, group ARN `group/caltech-poc-msk/*`)
  - S3 read on plugins bucket
  - SecretsManager read on Aurora secrets + MSK SCRAM secret
  - CloudWatch Logs write
  - VPC ENI permissions

> The MSK policy initially uses `msk_cluster_arn = "*"` because the IAM module is applied before MSK. After the full stack is up, the final `terraform apply` tightens it to the exact cluster ARN.

### 2.7 `ec2`

Generic EC2 launch template. Used 3× from `main.tf`:

| Module call | Name suffix | Purpose |
|---|---|---|
| `module.ec2` | `app-server` | Transaction simulator |
| `module.ec2_pg_sink` | `pg-sink-app-server` | PostgreSQL sink consumer |
| `module.ec2_redis_sink` | `redis-sink-app-server` | Redis sink consumer |

**Instance type per role:**
- `module.ec2` → `m6i.2xlarge` (8 vCPU, 32 GiB RAM) — heavier instance for the txn simulator
- `module.ec2_pg_sink` → `t3.xlarge` (4 vCPU, 16 GiB RAM)
- `module.ec2_redis_sink` → `t3.xlarge` (4 vCPU, 16 GiB RAM)

All 3 instances share these settings:
- 100 GB gp3 root volume, KMS-encrypted via `caltech-poc-ebs` key
- IMDSv2 enforced (`http_tokens = "required"`)
- No public IP — SSM access only
- IAM instance profile: `caltech-poc-ec2-app-role`
- Key pair: `caltech-keypair` (for emergency SSH from a jump host)

### 2.8 `aurora_source`

Aurora PostgreSQL **Serverless v2** with logical replication enabled — the standard CDC source for Debezium.

| Setting | Value |
|---|---|
| Cluster identifier | `caltech-poc-aurora-source` |
| Engine | `aurora-postgresql` |
| Engine version | `16.x` (configurable via `aurora_engine_version`) |
| Min/Max ACUs | 0.5 / 16 |
| Instance count | 1 (`db.serverless`) |
| Parameter group | Custom, with `rds.logical_replication=1`, `max_replication_slots=10`, `max_wal_senders=10`, `wal_sender_timeout=0` |
| Backup retention | 7 days |
| Deletion protection | **ON** |
| CloudWatch logs | `postgresql` |

### 2.9 `aurora_source_limitless`

Aurora PostgreSQL **Limitless Database** variant. Same purpose (CDC source) but uses horizontal sharding.

| Setting | Value |
|---|---|
| Cluster identifier | `caltech-poc-aurora-source-limitless` |
| Engine version | `16.13-limitless` |
| Cluster scalability type | `limitless` |
| Storage type | `aurora-iopt1` (I/O-Optimized — required) |
| Shard group | `caltech-poc-aurora-source-limitless-shard` |
| Min/Max ACUs (shard) | 16 / 32 |
| Compute redundancy | 0 (single AZ — change to 1 or 2 for HA) |
| Performance Insights | **Required** by Limitless (enabled with `performance-insights-retention-period 7`) |
| Enhanced Monitoring | **Required** by Limitless (60s interval, dedicated IAM role) |

**Implementation note:** The AWS Terraform provider (as of v5.100.0) always sends `engine_mode=provisioned` to the API, which Aurora Limitless rejects. This module bypasses the bug by creating the cluster and shard group via `aws rds create-db-cluster` and `aws rds create-db-shard-group` in `null_resource` provisioners. Cluster info is then exposed via a `data "aws_rds_cluster"` lookup. Destroy provisioners run the corresponding `delete` commands.

### 2.10 `aurora_sink`

Aurora PostgreSQL Serverless v2 — JDBC sink target.

| Setting | Value |
|---|---|
| Cluster identifier | `caltech-poc-aurora-sink` |
| Engine version | Same as `aurora_source` |
| Min/Max ACUs | 0.5 / 16 |
| Instance count | 1 (`db.serverless`) |
| Logical replication | OFF (sink doesn't need it) |
| Deletion protection | **ON** |

### 2.11 `msk`

Provisioned MSK cluster with both SASL/SCRAM and SASL/IAM authentication.

| Setting | Value |
|---|---|
| Cluster name | `caltech-poc-msk` |
| Kafka version | 3.9.x |
| Broker type | `kafka.m5.2xlarge` |
| Broker count | **3** (one per AZ — `us-west-2a`, `us-west-2b`, `us-west-2c`) |
| Storage per broker | 1000 GB EBS |
| Encryption at rest | KMS (`caltech-poc-secrets` key) |
| Encryption in transit | TLS (broker↔client, in-cluster) |
| Enhanced monitoring | `PER_BROKER` |
| Logs | CloudWatch (`/aws/msk/caltech-poc/broker`, 90d retention) |
| Custom broker config | `auto.create.topics.enable=true`, `default.replication.factor=3`, `min.insync.replicas=2`, `num.partitions=1`, `log.retention.hours=168` |
| SASL/SCRAM secret | `AmazonMSK_caltech-poc-scram` (username `kafkauser`) |

### 2.12 `msk_connect`

Generic MSK Connect connector module. Reused **6×** from `main.tf` — one Debezium source + 5 JDBC sinks. Each instantiation passes the full `connector_configuration` map.

| Module call | Connector name suffix | Plugin |
|---|---|---|
| `module.msk_connect` | `debezium-postgres-source-connector` | Debezium PostgreSQL |
| `module.msk_connect_sink` | `postgres-sink-connector-student-enrollment` | Confluent JDBC Sink |
| `module.msk_connect_sink_attendance` | `postgres-sink-connector-student-attendance` | Confluent JDBC Sink |
| `module.msk_connect_sink_lms` | `postgres-sink-connector-student-lms` | Confluent JDBC Sink |
| `module.msk_connect_sink_section_enrollments` | `postgres-sink-connector-section-enrollments` | Confluent JDBC Sink |
| `module.msk_connect_sink_term_log` | `postgres-sink-connector-student-term-log` | Confluent JDBC Sink |

**Worker config (per connector):**
- `key.converter` = `org.apache.kafka.connect.json.JsonConverter`
- `value.converter` = `org.apache.kafka.connect.json.JsonConverter`
- `schemas.enable` = `false` (matches source connector output — sinks would fail with `JsonConverter requires schema and payload` if `true`)

**Capacity:** Autoscaling, 1–2 workers, 1 MCU (vCPU/RAM unit), scale-in at 20% CPU, scale-out at 80% CPU.

### 2.13 `elasticache`

ElastiCache Serverless Redis cache.

| Setting | Value |
|---|---|
| Cache name | `caltech-poc-redis` |
| Engine | Redis (Serverless) |
| Min/Max storage | Configurable via `redis_min_data_storage_gb` / `redis_max_data_storage_gb` |
| Min/Max ECPU/s | Configurable via `redis_min_ecpu_per_second` / `redis_max_ecpu_per_second` |
| TLS | Always on |
| KMS | `caltech-poc-redis` key |

---

## 3. Network & Subnet Layout

```
VPC vpc-0ed44b92f11b73815 (existing — managed outside this stack)
│
├── Public subnets (2)
│   ├── subnet-038946a978f266b7d
│   └── subnet-052b8a9527604c064
│       ├── EC2 app-server (no public IP)
│       ├── EC2 pg-sink-app-server (no public IP)
│       ├── EC2 redis-sink-app-server (no public IP)
│       ├── VPC interface endpoints (SSM × 3)
│       └── S3 Gateway endpoint (public route tables)
│
└── Private subnets (3 — across us-west-2a, 2b, 2c)
    ├── subnet-0afa40d43201113c7  (used by: aurora_source, aurora_sink, aurora_limitless, msk, msk_connect, elasticache)
    ├── subnet-09fbbd79068ad5555  (used by: aurora_source, aurora_sink, aurora_limitless, msk, msk_connect, elasticache)
    └── subnet-069266bf3b71d537e  (used by: msk only — 3rd AZ for HA)
```

**External CIDR:** `10.145.0.0/24` (VM subnet) — allowed inbound on Aurora (5432), Redis (6379), and EC2 SSH (22).

---

## 4. Security Group Matrix

| From → To | EC2 | MSK | MSK Connect | Aurora Src | Aurora Sink | Redis |
|---|---|---|---|---|---|---|
| EC2 → | — | 9098, 9096 | — | 5432 | 5432 | 6379 |
| MSK Connect → | — | 9098, 9096, 9092, 9094 | — | 5432 | 5432 | — |
| VM CIDR → | 22, 8080 | — | — | 5432 | 5432 | 6379 |

---

## 5. IAM Roles & Trust Relationships

```
                  ┌─────────────────────────────────────┐
                  │ caltech-poc-ec2-app-role            │
                  │ Trust: ec2.amazonaws.com            │
                  │                                     │
                  │ - AmazonSSMManagedInstanceCore      │
                  │ - MSK SASL/IAM (cluster ARN)        │
                  │ - SecretsManager:GetSecretValue     │
                  │   (Aurora secrets)                  │
                  │ - S3 RW (data-lake, plugins)        │
                  └─────────────────────────────────────┘

                  ┌─────────────────────────────────────┐
                  │ caltech-poc-msk-connect-role        │
                  │ Trust: kafkaconnect.amazonaws.com   │
                  │                                     │
                  │ - MSK SASL/IAM:                     │
                  │   • Connect (cluster ARN)           │
                  │   • DescribeCluster                 │
                  │   • ReadData, WriteData (topics)    │
                  │   • AlterGroup (consumer groups)    │
                  │ - S3 read (plugins bucket)          │
                  │ - SecretsManager (Aurora + SCRAM)   │
                  │ - CloudWatch Logs write             │
                  │ - VPC ENI permissions               │
                  └─────────────────────────────────────┘

                  ┌─────────────────────────────────────┐
                  │ caltech-poc-aurora-source-limitless │
                  │   -monitoring-role                  │
                  │ Trust: monitoring.rds.amazonaws.com │
                  │                                     │
                  │ - AmazonRDSEnhancedMonitoringRole   │
                  └─────────────────────────────────────┘
```

---

## 6. Encryption Strategy

| Service | At rest | In transit | Key alias |
|---|---|---|---|
| EC2 EBS volumes | KMS CMK | n/a | `alias/caltech-poc-ebs` |
| Aurora Source / Sink | KMS CMK | TLS (`rds.force_ssl=1`) | `alias/caltech-poc-aurora` |
| Aurora Limitless | KMS CMK | TLS | `alias/caltech-poc-aurora` |
| MSK Provisioned | KMS CMK | TLS | `alias/caltech-poc-secrets` |
| ElastiCache | KMS CMK | TLS (always on) | `alias/caltech-poc-redis` |
| S3 buckets | KMS CMK | TLS | `alias/caltech-poc-s3` |
| Secrets Manager | KMS CMK | TLS | `alias/caltech-poc-secrets` |

All keys have **automatic rotation enabled** (yearly).

---

## 7. Aurora Source vs Sink vs Limitless

| | `aurora_source` | `aurora_sink` | `aurora_source_limitless` |
|---|---|---|---|
| Cluster identifier | `caltech-poc-aurora-source` | `caltech-poc-aurora-sink` | `caltech-poc-aurora-source-limitless` |
| Cluster type | Serverless v2 | Serverless v2 | Limitless (sharded) |
| Engine version | 16.x | 16.x | 16.13-limitless |
| `cluster_scalability_type` | (standard, default) | (standard, default) | `limitless` |
| Capacity model | ACU range (0.5–16) on a single instance | ACU range (0.5–16) on a single instance | ACU range (16–32) on a shard group |
| Storage type | Aurora Standard | Aurora Standard | Aurora I/O-Optimized (required) |
| Logical replication | **YES** (`rds.logical_replication=1`) | NO | Default (custom param group not supported in current code) |
| Performance Insights | Optional | Optional | **Required** |
| Enhanced Monitoring | Optional | Optional | **Required** |
| Provisioned via | Terraform `aws_rds_cluster` | Terraform `aws_rds_cluster` | AWS CLI via `null_resource` (provider bug workaround) |
| Provisioning time | 5–15 min | 5–15 min | 20–40 min |
| Use case | Debezium CDC source | JDBC sink target | High-throughput sharded source variant |

---

## 8. MSK Provisioned Cluster

### Connectivity

| Protocol | Port | Auth | Used by |
|---|---|---|---|
| SASL/SCRAM | 9096 | Username/password from Secrets Manager | App clients on EC2 |
| SASL/IAM | 9098 | AWS Sig v4 via IAM role | MSK Connect workers |
| Plaintext | 9092 | None | MSK Connect (intra-VPC) |
| TLS | 9094 | TLS only | MSK Connect (intra-VPC) |

### Custom broker configuration (`aws_msk_configuration`)

```
auto.create.topics.enable=true
default.replication.factor=3
min.insync.replicas=2
num.partitions=1
log.retention.hours=168
```

### Topics

CDC topics are auto-created when Debezium publishes the first event to them. Naming pattern:

```
caltech_poc_10.<schema>.<table>
```

Example: `caltech_poc_10.public.student_enrollment`

### Get bootstrap endpoints

```bash
terraform output msk_bootstrap_brokers          # SCRAM endpoint (port 9096) — for app
# IAM endpoint is consumed internally by MSK Connect module via module.msk.bootstrap_brokers_iam
```

---

## 9. MSK Connect — Source & Sink Connectors

### Source connector (Debezium)

| Setting | Value |
|---|---|
| Connector class | `io.debezium.connector.postgresql.PostgresConnector` |
| Plugin name | `caltech-poc-debezium-postgresql-source-connector-plugin` (uploaded to S3) |
| Topic prefix | `caltech_poc_10` |
| Plugin name (Postgres) | `pgoutput` |
| Slot name | Configurable via `debezium_slot_name` |
| Publication name | `dbz_publication` (auto-create mode `all_tables`) |
| Snapshot mode | Configurable (default `initial`) |
| Transforms | `unwrap` → `ExtractNewRecordState` (schema-less output) |
| Headers added | `op, ts_ms, source.ts_ms, before.<pk_cols>` |
| `schemas.enable` | `false` (key + value) |
| Tasks max | 1 (Debezium PostgreSQL caps at 1 internally) |

### Sink connectors (Confluent JDBC Sink, ×5)

| Setting | Value |
|---|---|
| Connector class | `io.confluent.connect.jdbc.JdbcSinkConnector` |
| Plugin name | `caltech-poc-postgres-sink-connector-plugin` (uploaded to S3) |
| Connection URL | `jdbc:postgresql://<aurora_sink_endpoint>:5432/<aurora_sink_db_name>` |
| Dialect | `PostgreSqlDatabaseDialect` |
| `auto.create` | `true` |
| `auto.evolve` | `true` |
| `insert.mode` | `upsert` |
| `delete.enabled` | `true` |
| `pk.mode` | `record_key` |
| `schemas.enable` | `false` (matches source — JsonConverter would otherwise reject schema-less messages) |
| `batch.size` | 5000 |
| Tasks max | 10 (Kafka caps at partition count of source topic) |

---

## 10. ElastiCache Redis

- Serverless cache (no node management)
- TLS always-on
- KMS encrypted at rest
- Min/max storage and ECPU/s configurable via variables

**Connect from EC2:**

```bash
redis-cli -h <redis_endpoint> -p 6379 --tls
```

---

## 11. EC2 App Servers

| Module | Instance name | Purpose |
|---|---|---|
| `module.ec2` | `caltech-poc-app-server` | Transaction simulator (writes to Aurora Source) |
| `module.ec2_pg_sink` | `caltech-poc-pg-sink-app-server` | PostgreSQL sink consumer logic (optional — JDBC sink connector does the actual writes) |
| `module.ec2_redis_sink` | `caltech-poc-redis-sink-app-server` | Redis sink consumer (writes from Kafka to Redis) |

### Access via SSM

```bash
# Any instance — substitute output name as appropriate
aws ssm start-session \
  --target $(terraform output -raw ec2_instance_id) \
  --region us-west-2 --profile default
```

### Bootstrap (commented user_data)

The EC2 module includes a commented-out `user_data` block that installs Java, AWS CLI, and the `aws-msk-iam-auth` JAR. To enable, uncomment in [`modules/ec2/main.tf`](./modules/ec2/main.tf) and apply.

---

## 12. State Management

### Backend

```hcl
# backend.hcl
bucket         = "caltech-terraform-state-342448511503"
key            = "prod-stack/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "caltech-terraform-lock"
encrypt        = true
```

### Lock table

`caltech-terraform-lock` (PAY_PER_REQUEST, PITR enabled by `init.sh`).

### Common state operations

```bash
# List all resources in state
terraform state list

# Show a specific resource
terraform state show module.aurora_source.aws_rds_cluster.this

# Move a resource (rename without recreate)
terraform state mv module.old_name module.new_name

# Remove a resource from state (does NOT delete in AWS)
terraform state rm module.aurora_source_limitless.null_resource.cluster

# Import an existing AWS resource into state
terraform import module.aurora_sink.aws_rds_cluster.this caltech-poc-aurora-sink

# Force-unlock a stale lock (use the lock ID from the error message)
terraform force-unlock <lock-id>
```

---

## 13. Operations Runbook

### Rotate an Aurora master password

```bash
# 1. Mark the random_password resource as tainted
terraform taint module.secrets.random_password.aurora_source

# 2. Apply — Terraform generates a new password and updates Secrets Manager
terraform apply -target=module.secrets

# 3. Update the cluster master password (lifecycle block ignores changes, so do it manually)
NEW_PW=$(aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw aurora_source_secret_arn) \
  --query SecretString --output text --profile default | jq -r '.password')

aws rds modify-db-cluster \
  --db-cluster-identifier caltech-poc-aurora-source \
  --master-user-password "$NEW_PW" \
  --apply-immediately \
  --region us-west-2 \
  --profile default

# 4. Restart sink/source connectors to pick up the new password
terraform apply \
  -replace=module.msk_connect.aws_mskconnect_connector.this \
  -target=module.msk_connect
```

### Restart a failed MSK Connect connector

```bash
# Easiest path — replace the connector resource
terraform apply \
  -replace=module.msk_connect_sink.aws_mskconnect_connector.this \
  -target=module.msk_connect_sink
```

### Check Limitless cluster status

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier caltech-poc-aurora-source-limitless \
  --region us-west-2 --profile default \
  --query "DBClusters[0].Status"

aws rds describe-db-shard-groups \
  --db-shard-group-identifier caltech-poc-aurora-source-limitless-shard \
  --region us-west-2 --profile default \
  --query "DBShardGroups[0].Status"
```

Both should return `available` when ready.

### Verify SG rules

```bash
# Aurora Sink SG — should have inbound 5432 from EC2 + MSK Connect + VM CIDR
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=caltech-poc-aurora-sink-sg" \
  --region us-west-2 --profile default \
  --query "SecurityGroups[0].IpPermissions" --output table
```

### Get all current outputs

```bash
terraform output
```

---

## 14. Disaster Recovery & Backups

| Service | Backup mechanism | Retention | Recovery |
|---|---|---|---|
| Aurora Source / Sink | Automated snapshots | 7 days (configurable) | Restore via `aws rds restore-db-cluster-from-snapshot` |
| Aurora Limitless | Automated snapshots | 7 days | Same as above |
| MSK | EBS snapshots (AWS-managed) | n/a (broker-level — for HA) | Multi-broker replication (factor 3) |
| ElastiCache Serverless | Automated daily snapshots | Configurable | Restore on new cluster from snapshot |
| Terraform state | S3 versioning + DynamoDB PITR | Forever (S3) / 35 days (DynamoDB) | Restore S3 object version |
| Secrets | Recovery window | Configurable (default 7 days) | `aws secretsmanager restore-secret` within the window |

### Aurora final snapshot

`skip_final_snapshot = false` and `final_snapshot_identifier = "<cluster>-final"` are set. On `terraform destroy`, Aurora creates a final snapshot before deletion. Override with `-var="aurora_skip_final_snapshot=true"` for non-prod tear-down.

---

## 15. Known Issues & Workarounds

### Aurora Limitless: provider sends `engine_mode=provisioned`

**Symptom:** `InvalidParameterCombination: Aurora Limitless Database doesn't support engine modes`

**Cause:** AWS Terraform provider (≤ v5.100.0) has `Default: "provisioned"` on `engine_mode` in the `aws_rds_cluster` schema. The default value is sent to the API even when the field is omitted from HCL.

**Fix:** The `aurora_source_limitless` module creates the cluster via AWS CLI in `null_resource` provisioners, bypassing the broken Terraform resource entirely.

### MSK Connect: failed worker config can't be deleted

**Symptom:** `BadRequestException: You can't delete a worker configuration being used by one or more connectors`

**Cause:** A connector created outside Terraform (or with a different name) is still using the worker config.

**Fix:** Delete the orphan connector in the AWS MSK console first, then re-run `terraform apply`.

### SG ingress: `InvalidPermission.Duplicate`

**Symptom:** `the specified rule "peer: sg-xxx, TCP, port N" already exists`

**Cause:** Someone manually added the rule via the AWS console — it now collides with Terraform-managed rules.

**Fix:** Either delete the manual rule in the console, or remove the rule from the Terraform code (and let the manual rule stand).

### Sink connector: `JsonConverter requires schema and payload`

**Symptom:** Tasks fail immediately on first message consumption.

**Cause:** Sink connector has `schemas.enable=true` but the source connector publishes schema-less JSON (because the source uses `ExtractNewRecordState` SMT with `schemas.enable=false`).

**Fix:** All sink connectors are configured with `converter_schemas_enabled = false` to match. If you change one, change both.

### MSK SG: 9096 from EC2 already exists

**Symptom:** Duplicate rule error specifically for port 9096 + EC2 SG.

**Cause:** `var.msk_scram_port = 9096` already creates an EC2→MSK inbound rule. Adding a second explicit rule for 9096 collides.

**Fix:** Don't add a second 9096 rule — the `var.msk_scram_port` rule handles it.

---

## 16. Cost Notes

Approximate monthly cost in `us-west-2` (USD, on-demand pricing, May 2026):

| Component | Cost driver | Estimate |
|---|---|---|
| Aurora Source (Serverless v2) | 0.5 ACU avg × $0.12/ACU-hr × 730 hr | ~$44 |
| Aurora Sink (Serverless v2) | 0.5 ACU avg × $0.12/ACU-hr × 730 hr | ~$44 |
| Aurora Limitless | 16 ACU min × $0.12/ACU-hr × 730 hr | **~$1,400** |
| MSK Provisioned | 3 × kafka.m5.2xlarge × ~$0.50/hr × 730 hr | ~$1,095 |
| MSK Connect | 1–2 workers × 1 MCU × ~$0.11/MCU-hr × 730 hr | ~$80 |
| EC2 — app-server (m6i.2xlarge) | 1 × ~$0.384/hr × 730 hr | ~$280 |
| EC2 — pg/redis sinks (×2 t3.xlarge) | 2 × ~$0.166/hr × 730 hr | ~$243 |
| ElastiCache Serverless | Min 1 GB + 1000 ECPU/s | ~$80 |
| EBS storage (MSK) | 3 × 1000 GB × $0.10/GB-mo | ~$300 |
| Data transfer | Variable | $50–200 |
| **Total (rough)** | | **~$3,673/month** |

> **Limitless is still a significant cost driver.** Min ACU is currently 16 (~$1,400/mo idle baseline). If the POC needs to reduce cost further, lower `aurora_limitless_min_acu` in `terraform.tfvars` (note: AWS imposes a hard floor on Limitless min ACU — verify the lowest allowed in your region).

---

## 17. Change Log

| Date | Change |
|---|---|
| 2026-05-29 | Updated README to include `aurora_source_limitless`, 3 EC2 modules, 5 sink connectors. Created `DOCUMENTATION.md`. |
| 2026-05-27 | Added Aurora Limitless module with `null_resource` workaround for provider bug. |
| 2026-05-25 | Added VPC endpoints for STS/SecretsManager. Fixed MSK SG to allow 9092/9094 from MSK Connect. |
| 2026-05-22 | Genericized `msk_connect` module. Added 5 JDBC sink connectors. Fixed schema mismatch (`schemas.enable=false` on sinks). |
| 2026-05-22 | Added 2nd and 3rd EC2 instances (`ec2_pg_sink`, `ec2_redis_sink`). |
| 2026-05-21 | Fixed MSK IAM topic/group ARNs (added `-msk` suffix to cluster name). |
| 2026-05-20 | Removed Kinesis Firehose. MSK uses CloudWatch logs only. |
| 2026-05-20 | Added MSK broker config with `auto.create.topics.enable=true`. |

---

**Document version:** 1.0 · **Last updated:** 2026-05-29
