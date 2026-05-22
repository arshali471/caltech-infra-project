# MSK & Debezium Connector — Configuration Reference

## 1. MSK Cluster

| Parameter | Value |
|-----------|-------|
| Cluster Name | `caltech-poc-msk` |
| Region | `us-west-2` |
| Kafka Version | `3.9.x` |
| Broker Count | `3` (one per AZ) |
| Broker Instance Type | `kafka.m5.2xlarge` |
| Storage per Broker | `1000 GB` (EBS gp2) |
| Encryption at Rest | KMS (AWS managed key) |
| Encryption in Transit | TLS (client ↔ broker and broker ↔ broker) |
| Enhanced Monitoring | `PER_BROKER` |

### Authentication — Two modes supported

| Mode | Port | Used By |
|------|------|---------|
| SASL/SCRAM | `9096` | App clients (EC2, consumers) |
| SASL/IAM | `9098` | MSK Connect (Debezium) |
| TLS | `9094` | App clients (TLS only) |
| Plaintext | `9092` | App clients |

### SCRAM Credentials
- Secret stored in **AWS Secrets Manager**: `AmazonMSK_caltech-poc-scram`
- Username: `kafkauser`
- Password: auto-generated 32-character string (retrieve from Secrets Manager)

### Broker Configuration
```
auto.create.topics.enable = true
default.replication.factor = 3
min.insync.replicas = 2
num.partitions = 1
log.retention.hours = 168  (7 days)
```

### Logs
- Broker logs → **CloudWatch**: `/aws/msk/caltech-poc/broker` (90-day retention)

---

## 2. MSK Connect — Debezium Connector

| Parameter | Value |
|-----------|-------|
| Connector Name | `caltech-poc-debezium-postgres-source-connector` |
| Kafka Connect Version | `3.7.x` |
| Plugin | Debezium PostgreSQL Connector `3.2.6` |
| Plugin Name (AWS) | `caltech-poc-debezium-postgresql-source-connector-plugin` |
| Authentication to MSK | IAM (SASL/IAM port 9098) |
| Encryption | TLS |
| Workers (min) | `1` |
| Workers (max) | `2` |
| MCU per Worker | `1` |
| Scale-in CPU threshold | `20%` |
| Scale-out CPU threshold | `80%` |

### Worker Configuration
```
key.converter   = org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable   = false
value.converter = org.apache.kafka.connect.json.JsonConverter
value.converter.schemas.enable = false
```

### Connector Logs
- Worker logs → **CloudWatch**: `/aws/mskconnect/caltech-poc` (90-day retention)

---

## 3. Debezium Connector Configuration

### Source Database (Aurora PostgreSQL)
| Parameter | Value |
|-----------|-------|
| `connector.class` | `io.debezium.connector.postgresql.PostgresConnector` |
| `database.hostname` | Aurora Source cluster endpoint (from Terraform output) |
| `database.port` | `5432` |
| `database.dbname` | `sourcedb` |
| `database.user` | `dbadmin` |
| `database.password` | Stored in Secrets Manager |

### CDC Settings
| Parameter | Value |
|-----------|-------|
| `plugin.name` | `pgoutput` |
| `slot.name` | `dbz_students_slot` |
| `slot.drop.on.stop` | `false` |
| `publication.name` | `dbz_publication` |
| `publication.autocreate.mode` | `all_tables` |
| `snapshot.mode` | `initial` |
| `tasks.max` | `1` |
| `heartbeat.interval.ms` | `30000` (30 seconds) |

### Tables Captured
| Table | Kafka Topic |
|-------|-------------|
| `public.section_enrollments` | `caltech_poc_10.public.section_enrollments` |
| `public.student_attendance` | `caltech_poc_10.public.student_attendance` |
| `public.student_enrollment` | `caltech_poc_10.public.student_enrollment` |
| `public.student_lms` | `caltech_poc_10.public.student_lms` |
| `public.student_term_log` | `caltech_poc_10.public.student_term_log` |

- `topic.prefix` = `caltech_poc_10`
- `schema.include.list` = `public`
- `table.include.list` = `public.section_enrollments, public.student_attendance, public.student_enrollment, public.student_lms, public.student_term_log`

### Data Type Handling
| Parameter | Value |
|-----------|-------|
| `decimal.handling.mode` | `double` |
| `time.precision.mode` | `connect` |

---

## 4. Single Message Transform (SMT)

Transform: **ExtractNewRecordState** (unwrap Debezium envelope)

| Parameter | Value |
|-----------|-------|
| `transforms` | `unwrap` |
| `transforms.unwrap.type` | `io.debezium.transforms.ExtractNewRecordState` |
| `transforms.unwrap.drop.tombstones` | `false` |
| `transforms.unwrap.delete.handling.mode` | `drop` |

### Headers added to each message
```
op
ts_ms
source.ts_ms
before.external_sourced_id
before.student_id
before.term_id
before.student_enrollment_id
before.section_id
```

---

## 5. Kafka Topic Format

Topics are auto-created by Debezium on first write.

Format: `{topic.prefix}.{schema}.{table}`

All 5 topics:
```
caltech_poc_10.public.section_enrollments
caltech_poc_10.public.student_enrollment
caltech_poc_10.public.student_lms
caltech_poc_10.public.student_attendance
caltech_poc_10.public.student_term_log
```

---

## 6. Security Groups — MSK

| Inbound Port | Protocol | Source | Purpose |
|--------------|----------|--------|---------|
| `9092` | TCP | MSK Connect SG | Plaintext |
| `9094` | TCP | MSK Connect SG | TLS |
| `9096` | TCP | EC2 SG + MSK Connect SG | SASL/SCRAM |
| `9098` | TCP | EC2 SG + MSK Connect SG | SASL/IAM |

## 6b. Security Groups — Aurora Source

| Inbound Port | Protocol | Source | Purpose |
|--------------|----------|--------|---------|
| `5432` | TCP | EC2 SG | App clients |
| `5432` | TCP | MSK Connect SG | Debezium CDC reads |

---

## 7. IAM — MSK Connect Service Execution Role

Role: `caltech-poc-msk-connect-role`

Permissions granted:
```
kafka-cluster:Connect          → caltech-poc-msk cluster ARN
kafka-cluster:AlterCluster     → caltech-poc-msk cluster ARN
kafka-cluster:DescribeCluster  → caltech-poc-msk cluster ARN
kafka-cluster:*Topic*          → arn:aws:kafka:us-west-2:342448511503:topic/caltech-poc-msk/*
kafka-cluster:WriteData        → arn:aws:kafka:us-west-2:342448511503:topic/caltech-poc-msk/*
kafka-cluster:ReadData         → arn:aws:kafka:us-west-2:342448511503:topic/caltech-poc-msk/*
kafka-cluster:AlterGroup       → arn:aws:kafka:us-west-2:342448511503:group/caltech-poc-msk/*
kafka-cluster:DescribeGroup    → arn:aws:kafka:us-west-2:342448511503:group/caltech-poc-msk/*
```

Also has permissions for:
- S3 (plugin bucket read, logs bucket write)
- Secrets Manager (Aurora source secret read)
- CloudWatch Logs (worker log delivery)
- EC2 VPC networking (create/delete network interfaces)

---

## 8. How to Get Bootstrap Brokers

Run from the EC2 instance or AWS CLI:
```bash
# IAM bootstrap (port 9098) — used by MSK Connect
aws kafka get-bootstrap-brokers --cluster-arn <cluster-arn> --region us-west-2 \
  --query 'BootstrapBrokerStringSaslIam' --output text

# SCRAM bootstrap (port 9096) — used by app clients
aws kafka get-bootstrap-brokers --cluster-arn <cluster-arn> --region us-west-2 \
  --query 'BootstrapBrokerStringSaslScram' --output text
```

Or via Terraform output:
```bash
terraform output msk_bootstrap_brokers_iam    # port 9098 - IAM
terraform output msk_bootstrap_brokers_scram  # port 9096 - SCRAM
```
