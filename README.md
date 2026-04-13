# California Project — Terraform Infrastructure

> **Cloud:** AWS `us-west-1`  
> **Stack:** Serverless Kubernetes (EKS Fargate) + Serverless Kafka (MSK Serverless) + Serverless PostgreSQL (Aurora Serverless v2 × 2) + Serverless Redis (ElastiCache Serverless) + ALB  
> **IaC:** Terraform ≥ 1.5 · AWS Provider ~> 5.0  
> **Philosophy:** 100% serverless — zero EC2 nodes or brokers to manage, patch, or right-size

---

## Table of Contents

1. [What We Are Building](#what-we-are-building)  
2. [Architecture Overview](#architecture-overview)  
3. [Repository Structure](#repository-structure)  
4. [Terraform Modules](#terraform-modules)  
5. [How Data Flows](#how-data-flows)  
6. [Security Design](#security-design)  
7. [Production Best Practices Applied](#production-best-practices-applied)  
8. [Prerequisites](#prerequisites)  
9. [How to Deploy](#how-to-deploy)  
10. [How to Destroy](#how-to-destroy)  
11. [Module Input Variables Reference](#module-input-variables-reference)  
12. [Outputs Reference](#outputs-reference)  
13. [Common Operations](#common-operations)  
14. [Troubleshooting](#troubleshooting)

---

## What We Are Building

This project provisions a **production-grade, multi-tier AWS infrastructure** for the California platform. It is designed around a **Kubernetes-native microservices architecture** backed by a **Change Data Capture (CDC) pipeline** using Kafka and Debezium.

### Core Services

| Layer | Service | Serverless Mode | Purpose |
|-------|---------|-----------------|----------|
| **Ingress** | Application Load Balancer (ALB) | Managed (no instances) | Public HTTPS entry point — routes traffic to EKS Fargate pods |
| **Compute** | Amazon EKS + Fargate Profiles | ✅ **EKS Fargate** — no EC2 nodes | Runs all application workloads, ingress controller, and Debezium CDC connector |
| **Streaming** | Amazon MSK Serverless | ✅ **MSK Serverless** — no brokers to size | Event backbone — SASL/IAM auth only, port 9098, auto-scales to any throughput |
| **CDC** | Debezium (EKS Fargate pod) | ✅ Runs on Fargate | Streams database changes from Aurora CDC source into Kafka topics in real time |
| **Primary DB** | Aurora PostgreSQL Serverless v2 | ✅ **Aurora Serverless v2** — 0.5–64 ACUs | Main transactional database — ACU-based auto-scaling, writer + readers |
| **CDC Source DB** | Aurora PostgreSQL Serverless v2 | ✅ **Aurora Serverless v2** — 0.5–32 ACUs | CDC source — logical replication enabled for Debezium |
| **Cache** | ElastiCache Serverless Redis | ✅ **ElastiCache Serverless** — 1–10 GB, ECPU-based | High-speed caching, session storage, Kafka sink target |

---

## Architecture Overview

See [ARCHITECTURE.md](./ARCHITECTURE.md) for full interactive Mermaid diagrams.

**Three-tier network design:**

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  VPC  10.0.0.0/16                                            us-west-1   │
│                                                                          │
│  ┌──────────────────────┐  ┌──────────────────────────────────────────┐  │
│  │  PUBLIC SUBNET       │  │  PRIVATE APP SUBNET                      │  │
│  │  10.0.1.0/24 (AZ-a)  │  │  10.0.11.0/24 (AZ-a)                    │  │
│  │  10.0.2.0/24 (AZ-c)  │  │  10.0.12.0/24 (AZ-c)                    │  │
│  │                      │  │                                          │  │
│  │  • ALB (internet)    │  │  • EKS Control Plane (private API)       │  │
│  │  • NAT GW × 2        │  │  • EKS Worker Nodes                      │  │
│  │  • Internet Gateway  │  │  • MSK Kafka Brokers × 2                 │  │
│  │                      │  │  • Debezium CDC (EKS pod)                │  │
│  └──────────────────────┘  └──────────────────────────────────────────┘  │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │  PRIVATE DB SUBNET  (no internet route — fully sealed)              │ │
│  │  10.0.21.0/24 (AZ-a)    10.0.22.0/24 (AZ-c)                        │ │
│  │                                                                     │ │
│  │  • Aurora PostgreSQL (writer + readers, auto-scale)                 │ │
│  │  • RDS PostgreSQL  (Multi-AZ, CDC source for Debezium)              │ │
│  │  • ElastiCache Redis  (Primary + Replica, Multi-AZ failover)        │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
CaliforniaProject/
│
├── versions.tf          # Required provider versions (aws ~>5, tls, kubernetes, random)
├── backend.tf           # Remote state: S3 bucket + DynamoDB lock table
├── providers.tf         # AWS + Kubernetes provider configuration
├── variables.tf         # All root-level input variables with descriptions & defaults
├── terraform.tfvars     # Production values (override defaults here)
├── data.tf              # Data sources (account ID, current region)
├── main.tf              # Root: instantiates all 7 modules and wires them together
├── outputs.tf           # Root-level outputs (endpoints, ARNs, etc.)
├── ARCHITECTURE.md      # Visual diagrams (Mermaid) — this file
├── README.md            # Full project documentation — this file
│
└── modules/
    ├── vpc/             # Module 1 — VPC, subnets, routing, security groups
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── alb/             # Module 2 — Application Load Balancer
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── eks/             # Module 3 — EKS cluster, Fargate profiles, OIDC/IRSA, SGP
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── msk/             # Module 4 — MSK Serverless (SASL/IAM only, no brokers to configure)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── aurora/          # Module 5 — Aurora Serverless v2, ACU scaling, Secrets Manager
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    ├── rds/             # Module 6 — Aurora Serverless v2 CDC source (logical replication)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    │
    └── elasticache/     # Module 7 — ElastiCache Serverless Redis, CloudWatch alarms
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## Terraform Modules

### Module 1 — `vpc`

**What it creates:**
- 1 VPC with DNS resolution enabled
- 2 Public subnets (1 per AZ) — tagged for AWS Load Balancer Controller
- 2 Private App subnets (1 per AZ) — tagged for internal ELB
- 2 Private DB subnets (1 per AZ) — no internet route
- Internet Gateway (for public subnets)
- 2 NAT Gateways (1 per AZ — eliminates cross-AZ NAT traffic for HA)
- Route tables: public → IGW, private-app → NAT, private-db → no route
- RDS DB Subnet Group (shared by Aurora + RDS)
- ElastiCache Subnet Group
- VPC Flow Logs → CloudWatch (90-day retention)
- 6 Security Groups (ALB, EKS cluster, EKS nodes, MSK, RDS, Aurora, ElastiCache)

**Why it is the foundation:** All other modules receive their VPC IDs, subnet IDs, and security group IDs as outputs from this module.

---

### Module 2 — `alb`

**What it creates:**
- Internet-facing Application Load Balancer in public subnets
- S3 bucket for ALB access logs (versioned, encrypted)
- HTTP listener (port 80) → redirects to HTTPS (HTTP 301)
- HTTPS listener (port 443) — uses TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.3)
- Default target group (IP type — works with EKS pods via Load Balancer Controller)
- Health check configuration (fully configurable via variables)
- Deletion protection enabled

**Traffic path:** `Internet → ALB → EKS Ingress → Kubernetes Service → Pod`

---

### Module 3 — `eks`

**What it creates:**
- EKS Cluster (Kubernetes 1.29, private API endpoint only)
- KMS key for Kubernetes secrets envelope encryption
- IAM role for the cluster control plane
- CloudWatch Log Group for all 5 control-plane log types
- OIDC Provider for IRSA (IAM Roles for Service Accounts)
- IAM role for worker nodes (with SSM access for shell-less debugging)
- Multiple Managed Node Groups (fully configurable — instance type, size, taints, labels)
- EKS Add-ons: `vpc-cni` (with `ENABLE_POD_ENI=true` for Security Groups for Pods), `kube-proxy`, `coredns`

**Key production features — Fargate specific:**
- **No EC2 worker nodes** — AWS provisions and manages the underlying compute per pod
- **Security Groups for Pods (SGP)** — `ENABLE_POD_ENI=true` on vpc-cni; pods carry `eks-pods-sg` directly
- **No EBS CSI driver** — EBS is not supported on Fargate; use EFS or S3 CSI for persistent storage
- IRSA enabled — pods get scoped IAM roles via OIDC; Debezium pods use IRSA for MSK SASL/IAM

---

### Module 4 — `msk`

**What it creates:**
- **MSK Serverless cluster** (`aws_msk_serverless_cluster`)
- VPC placement (subnet IDs + security group IDs)
- SASL/IAM client authentication (the only supported auth method for MSK Serverless)

**What MSK Serverless manages automatically (not configurable):**
- Broker provisioning, scaling, and replication
- Storage (no EBS; fully managed by AWS)
- Kafka version upgrades
- Encryption at rest and in transit (always on, AWS-managed keys)
- Cross-AZ broker placement for HA

**Client configuration for Debezium / application pods:**
- Bootstrap endpoint: `bootstrap_brokers_sasl_iam` output (sensitive)
- Port: `9098` (SASL/IAM only — no 9092/9094/9096)
- Authentication: AWS Signature v4 via IRSA on EKS Fargate pods

**Purpose in CDC pipeline:** MSK Serverless is the central event bus. Debezium writes CDC events to Kafka topics. Kafka sink connectors stream data to Aurora and Redis.

---

### Module 5 — `aurora`

**What it creates:**
- **Aurora PostgreSQL Serverless v2 cluster** (`engine_mode = "provisioned"` + `serverlessv2_scaling_configuration`)
- KMS key for storage encryption
- Secrets Manager secret for master credentials (password auto-generated, never stored in code)
- Custom cluster and instance parameter groups (family derived from `engine_version`)
- `instance_count` cluster instances with `instance_class = "db.serverless"` (scales between min/max ACUs)
- IAM role for enhanced monitoring (60-second granularity)
- Application Auto Scaling for read replicas (CPU-based, configurable target/min/max)
- Performance Insights enabled

**Aurora Serverless v2 scaling:** Each instance scales between `min_capacity_units` (default 0.5 ACU) and `max_capacity_units` (default 64 ACU). 1 ACU ≈ 2 GiB RAM. Scaling is online with no downtime.

**Role:** Primary transactional database for application workloads. Receives replicated data from Kafka sink connectors.

---

### Module 6 — `rds`

**What it creates:**
- **Aurora PostgreSQL Serverless v2 cluster** (CDC source — `engine_mode = "provisioned"` + `serverlessv2_scaling_configuration`)
- KMS key for storage encryption
- Secrets Manager secret for master credentials
- **Cluster parameter group — logical replication for Debezium CDC:**
  - `rds.logical_replication = 1` — enables WAL logical decoding
  - `max_wal_senders = 10` — up to 10 replication connections
  - `max_replication_slots = 10` — up to 10 concurrent Debezium slots
  - `wal_sender_timeout = 0` — disables WAL sender timeout (required for Debezium)
  - `rds.force_ssl = 1` — enforces TLS for all connections
- Instance parameter group (`log_connections`, `log_disconnections`)
- `instance_count` instances with `instance_class = "db.serverless"` — scales between 0.5–32 ACUs
- Enhanced monitoring, Performance Insights, deletion protection, automated backups

**Role:** CDC source database. Debezium captures row-level changes via PostgreSQL logical replication and streams them as events to MSK Serverless. Aurora Serverless v2 is used here so the CDC source also scales automatically with capture load.

---

### Module 7 — `elasticache`

**What it creates:**
- **ElastiCache Serverless cache** (`aws_elasticache_serverless_cache`, Redis engine)
- KMS key for at-rest encryption
- Capacity limits: `max_data_storage_gb` / `min_data_storage_gb` (GB) + `max_ecpu_per_second` / `min_ecpu_per_second` (ECPU/s)
- Automated daily snapshots (configurable `daily_snapshot_time`)
- CloudWatch alarms: `ElastiCacheProcessingUnits` > threshold, `BytesUsedForCache` > threshold

**What ElastiCache Serverless manages automatically:**
- Node type selection and scaling (no `node_type` or `num_cache_clusters`)
- High availability across AZs (built-in)
- Encryption in transit (always-on TLS)
- No parameter group, no auth token required

**Role:** High-speed caching layer. Receives hot data from Kafka sink connectors. Serves read-heavy requests with sub-millisecond latency. Scales storage and compute independently.

---

## How Data Flows

### User Request Flow
```
User → HTTPS:443 → ALB
     → EKS Ingress Controller (Fargate pod)
     → Application Pod (EKS Fargate)
     → Aurora Serverless v2 (writes) / ElastiCache Serverless Redis (reads/cache)
```

### CDC (Change Data Capture) Flow
```
Aurora Serverless v2 (CDC source)
  └─ WAL Logical Replication Slot (rds.logical_replication=1)
       └─ Debezium Connector (EKS Fargate pod, debezium namespace)
              │ SASL/IAM → MSK Serverless (port 9098)
              └─ Produce change events → MSK Serverless Kafka topic (per table)
                    ├─ JDBC Sink Connector → Aurora Serverless v2 primary
                    └─ Redis Sink Connector → ElastiCache Serverless Redis
```

**Why CDC?** CDC allows near-real-time data synchronisation between the source database and Aurora/Redis consumers without polling, reducing database load and latency.

---

## Security Design

### Encryption at Rest
| Service               | Mechanism                                   |
|-----------------------|---------------------------------------------|
| EKS Secrets           | KMS (dedicated key per cluster)             |
| MSK Serverless        | AWS-managed (always on, not configurable)   |
| Aurora Serverless v2  | KMS (dedicated key)                         |
| RDS/CDC Serverless v2 | KMS (dedicated key)                         |
| ElastiCache Serverless| KMS (dedicated key)                         |
| S3 buckets            | SSE-S3 (ALB logs)                           |
| Secrets Manager       | KMS (reuses service KMS key)                |

### Encryption in Transit
| Connection                           | Protocol                                  |
|--------------------------------------|-------------------------------------------|
| Internet → ALB                       | TLS 1.3                                   |
| ALB → EKS Fargate pods               | HTTP (within VPC, SG-controlled)          |
| EKS Fargate → Aurora/RDS             | SSL enforced via `rds.force_ssl=1`        |
| EKS Fargate → ElastiCache Serverless | TLS (always-on, not configurable)         |
| EKS Fargate → MSK Serverless         | TLS + SASL/IAM (AWS Sig v4, port 9098)    |

### Credential Management
- **No passwords in code.** All passwords are auto-generated by Terraform's `random_password` and stored exclusively in AWS Secrets Manager.
- **No static AWS keys in pods.** IRSA gives pods scoped IAM permissions. Debezium uses IRSA to authenticate to MSK Serverless via SASL/IAM without any access key.
- **No Redis auth token.** ElastiCache Serverless access is controlled by VPC security groups only — no auth token needed.

### Network Isolation
- DB subnet has **no route to Internet** — completely isolated from external traffic.
- Security groups use CIDR-based inbound rules (app subnet CIDRs `10.0.11.0/24`, `10.0.12.0/24`) for DB/cache/MSK because Fargate pods carry their own SG via SGP.
- EKS Fargate pods carry `eks-pods-sg` via **Security Groups for Pods** (`ENABLE_POD_ENI=true`) — pod-level network policy without EC2 node involvement.
- EKS API server endpoint is **private only** (`endpoint_public_access = false`).
- VPC Flow Logs capture all traffic for audit and incident response.

---

## Production Best Practices Applied

| Practice | Implementation |
|----------|----------------|
| **Remote state** | S3 bucket (versioned + encrypted) + DynamoDB lock |
| **Modular design** | 7 reusable modules — each independently testable and deployable |
| **No hardcoded values** | Every configurable value is a variable with a sensible default |
| **KMS encryption** | Dedicated KMS key per service with automatic key rotation |
| **Secrets rotation** | Secrets Manager stores all credentials; passwords never in `.tf` or `.tfvars` |
| **Multi-AZ HA** | Aurora Serverless v2 multi-instance, ElastiCache Serverless (built-in HA), MSK Serverless (AWS-managed), 2 NAT GWs |
| **No node management** | EKS Fargate — no worker node patching, AMI updates, or right-sizing |
| **IRSA** | OIDC provider attached; pods get IAM roles — no static keys |
| **Enhanced monitoring** | RDS/Aurora enhanced monitoring at 60s intervals + Performance Insights |
| **Deletion protection** | Enabled on ALB, Aurora, RDS |
| **Final snapshots** | Configured for Aurora and RDS before deletion |
| **VPC Flow Logs** | Captures all VPC traffic for audit and SOC 2 compliance |
| **Resource tagging** | All resources tagged with `Environment`, `Project`, `ManagedBy`, `Module` |
| **TLS 1.3** | ALB HTTPS listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06` |

---

## Prerequisites

Before running Terraform, ensure the following are in place:

### 1. Terraform CLI

```bash
terraform version  # Requires >= 1.5.0
```

### 2. AWS CLI + Credentials

```bash
aws configure  # Or use IAM role / environment variables
aws sts get-caller-identity  # Verify correct account
```

The deploying IAM role/user needs these minimum policies:
- `AdministratorAccess` (for initial setup)  
- OR granular: EC2, VPC, EKS, RDS, ElastiCache, MSK, KMS, SecretsManager, IAM, S3, CloudWatch, AppAutoScaling

### 3. Create Remote State Backend (One-time)

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket california-prod-terraform-state \
  --region us-west-1 \
  --create-bucket-configuration LocationConstraint=us-west-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket california-prod-terraform-state \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket california-prod-terraform-state \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name california-prod-terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-1
```

### 4. ACM Certificate (Optional — for HTTPS)

If you want HTTPS on the ALB, request a certificate in ACM and set in `terraform.tfvars`:
```hcl
alb_ssl_certificate_arn = "arn:aws:acm:us-west-1:YOUR_ACCOUNT_ID:certificate/CERT_ID"
```

---

## How to Deploy

```bash
# 1. Clone the repository and navigate to project root
cd CaliforniaProject/

# 2. Review and customise settings
vi terraform.tfvars

# 3. Initialise — downloads providers and sets up backend
terraform init

# 4. Review what will be created (ALWAYS do this first)
terraform plan -out=tfplan

# 5. Review the plan carefully, then apply
terraform apply tfplan
```

### Expected apply time: ~20–30 minutes
(EKS cluster takes ~10 min, Aurora takes ~5 min, MSK takes ~10 min)

### Get outputs after apply

```bash
# All outputs
terraform output

# Get EKS kubeconfig
aws eks update-kubeconfig \
  --region us-west-1 \
  --name $(terraform output -raw eks_cluster_name)

# Get Aurora endpoint
terraform output aurora_cluster_endpoint

# Get Redis endpoint
terraform output redis_primary_endpoint
```

---

## How to Destroy

> ⚠️ **WARNING:** Destroying production infrastructure is irreversible. Ensure backups exist.

```bash
# Step 1 — Disable deletion protection first (required for ALB, Aurora, RDS)
# Edit terraform.tfvars:
#   alb_deletion_protection = false
#   aurora_deletion_protection = false   (in module call)
#   rds_deletion_protection = false      (in module call)

terraform apply  # Apply the protection changes

# Step 2 — Destroy
terraform destroy
```

---

## Module Input Variables Reference

### `vpc` Module

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block |
| `availability_zones` | list(string) | — | AZs to deploy into |
| `public_subnet_cidrs` | list(string) | — | Public subnet CIDRs (1 per AZ) |
| `private_app_subnet_cidrs` | list(string) | — | App subnet CIDRs |
| `private_db_subnet_cidrs` | list(string) | — | DB subnet CIDRs |
| `single_nat_gateway` | bool | `false` | Use 1 NAT GW (cost saving, not HA) |
| `enable_flow_logs` | bool | `true` | Enable VPC flow logs |
| `flow_log_retention_days` | number | `90` | Flow log CW retention |

### `eks` Module

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_version` | string | `1.29` | Kubernetes version |
| `fargate_profiles` | map(object) | apps, debezium | Fargate profile definitions (namespace selectors) |
| `cluster_endpoint_public_access` | bool | `false` | Expose API to internet |
| `enable_irsa` | bool | `true` | Enable OIDC/IRSA |
| `kms_deletion_window_in_days` | number | `7` | KMS key deletion window |
| `log_retention_days` | number | `90` | CW control-plane log retention |

### `msk` Module

MSK Serverless has no broker-specific variables. AWS manages all broker scaling, storage, and replication.

| Variable | Type | Description |
|----------|------|-------------|
| `cluster_name` | string | MSK Serverless cluster name |
| `subnet_ids` | list(string) | Private app subnet IDs for broker ENI placement |
| `security_group_ids` | list(string) | Security group IDs (port 9098 SASL/IAM only) |
| `tags` | map(string) | Resource tags |

### `aurora` Module

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `engine_version` | string | `15.4` | PostgreSQL version |
| `instance_count` | number | `2` | Writer + reader instances (all `db.serverless`) |
| `min_capacity_units` | number | `0.5` | Min ACUs per instance |
| `max_capacity_units` | number | `64` | Max ACUs per instance |
| `autoscaling_min_replicas` | number | `1` | Min read replicas |
| `autoscaling_max_replicas` | number | `5` | Max read replicas |
| `autoscaling_cpu_target` | number | `70` | CPU % to scale read replicas |
| `monitoring_interval` | number | `60` | Enhanced monitoring (seconds) |
| `performance_insights_retention` | number | `7` | PI retention (days) |

### `rds` Module (Aurora Serverless v2 — CDC Source)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `engine_version` | string | `15.4` | Aurora PostgreSQL version |
| `instance_count` | number | `2` | Writer + reader instances (all `db.serverless`) |
| `min_capacity_units` | number | `0.5` | Min ACUs per instance |
| `max_capacity_units` | number | `32` | Max ACUs per instance |
| `max_wal_senders` | number | `10` | Max WAL sender processes |
| `max_replication_slots` | number | `10` | Max replication slots |
| `log_statement` | string | `ddl` | PostgreSQL log_statement level |
| `monitoring_interval` | number | `60` | Enhanced monitoring (seconds) |

### `elasticache` Module (ElastiCache Serverless)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `major_engine_version` | string | `7` | Redis major version |
| `max_data_storage_gb` | number | `10` | Max data storage (GB) |
| `min_data_storage_gb` | number | `1` | Min data storage (GB) |
| `max_ecpu_per_second` | number | `5000` | Max ECPU per second |
| `min_ecpu_per_second` | number | `1000` | Min ECPU per second |
| `snapshot_retention_limit` | number | `5` | Daily snapshot retention (days) |
| `alarm_ecpu_threshold` | number | `4000` | ECPU alarm threshold |
| `alarm_memory_threshold_gb` | number | `8` | Memory alarm threshold (GB) |

### `alb` Module

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ssl_certificate_arn` | string | `""` | ACM cert for HTTPS |
| `ssl_policy` | string | `ELBSecurityPolicy-TLS13-1-2-2021-06` | TLS cipher policy |
| `health_check_path` | string | `/healthz` | Health check URL path |
| `target_group_port` | number | `80` | Backend port |
| `deregistration_delay` | number | `60` | Drain seconds |
| `deletion_protection` | bool | `true` | Prevent accidental delete |

---

## Outputs Reference

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `eks_cluster_name` | EKS cluster name (use in `aws eks update-kubeconfig`) |
| `eks_cluster_endpoint` | EKS API server endpoint (sensitive) |
| `eks_oidc_provider_arn` | OIDC ARN for creating IRSA roles for pods |
| `alb_dns_name` | ALB DNS — add as CNAME in Route 53 |
| `msk_bootstrap_brokers_sasl_iam` | MSK Serverless bootstrap servers — SASL/IAM only (sensitive) |
| `aurora_cluster_endpoint` | Aurora Serverless v2 write endpoint (sensitive) |
| `aurora_reader_endpoint` | Aurora Serverless v2 read endpoint (sensitive) |
| `rds_cluster_endpoint` | Aurora Serverless v2 CDC source write endpoint (sensitive) |
| `rds_reader_endpoint` | Aurora Serverless v2 CDC source read endpoint (sensitive) |
| `redis_primary_endpoint` | ElastiCache Serverless Redis primary endpoint (sensitive) |
| `redis_reader_endpoint` | ElastiCache Serverless Redis reader endpoint (sensitive) |

---

## Common Operations

### Add a Fargate Profile for a new namespace

```hcl
# In terraform.tfvars:
eks_fargate_profiles = {
  apps     = { selectors = [{ namespace = "default",    labels = {} }] }
  debezium = { selectors = [{ namespace = "debezium",   labels = {} }] }
  payments = { selectors = [{ namespace = "payments",   labels = {} }] }  # new
}
```
```bash
terraform apply
```

### Scale Aurora Serverless v2 capacity

```hcl
# In terraform.tfvars:
aurora_max_capacity_units = 128   # raise from 64
rds_max_capacity_units    = 64    # raise from 32
```
```bash
terraform apply
```

### Rotate Database Password

```bash
# Taint the random_password resource to force a new one
terraform taint module.aurora.random_password.aurora_master
terraform apply
# The new password is automatically stored in Secrets Manager
```

### Get a database password from Secrets Manager

```bash
aws secretsmanager get-secret-value \
  --secret-id california-prod-aurora/master-credentials \
  --region us-west-1 \
  --query SecretString --output text | jq .

aws secretsmanager get-secret-value \
  --secret-id california-prod-postgres/master-credentials \
  --region us-west-1 \
  --query SecretString --output text | jq .
```

### Get MSK Serverless bootstrap endpoint

```bash
terraform output msk_bootstrap_brokers_sasl_iam
```

Configure your Kafka client (Debezium / application) with:
```properties
bootstrap.servers=<value from above>
security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler
```

### Connect to EKS

```bash
aws eks update-kubeconfig \
  --region us-west-1 \
  --name california-prod-eks
kubectl get nodes
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---------|-------------|-----|
| `terraform init` fails | Backend S3/DynamoDB not created | Run the backend creation commands in Prerequisites |
| EKS pod stuck `Pending` | No matching Fargate profile for namespace | Add the pod's namespace to `eks_fargate_profiles` in `terraform.tfvars` |
| Debezium can't connect to Aurora CDC | `rds.logical_replication` not yet active | Parameter group change requires instance reboot — `aws rds reboot-db-instance --db-instance-identifier <id>` |
| Debezium MSK auth error | IRSA not configured on Fargate pod | Ensure Debezium service account has IRSA IAM role with MSK `kafka-cluster:*` permissions |
| Kafka producer/consumer error | Wrong port or auth method | MSK Serverless uses port `9098` with SASL/IAM only — no port 9092/9094/9096 |
| ALB returning 502 | Fargate pod not healthy | Check `/healthz` endpoint; verify `eks-pods-sg` allows ALB ingress on ephemeral port range |
| Aurora not scaling | ACU ceiling too low | Raise `aurora_max_capacity_units` or `rds_max_capacity_units` in `terraform.tfvars` |
| `Error acquiring lock` | Another `terraform apply` is running | Check DynamoDB `california-prod-terraform-lock` for stale lock |
