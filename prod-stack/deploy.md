# Caltech DEV — Deployment Guide for the Client AWS Account

> Step-by-step guide for deploying the Caltech CDC pipeline (`prod-stack`) into the **client AWS account** using Terraform CLI.
>
> **Target environment:** `dev` in **`us-east-2`** (Ohio)
> **State storage:** S3 bucket `tfstate-imss-shared-342448511503-us-west-2` (us-west-2)
> **Lock mechanism:** S3 native (`use_lockfile = true`) — no DynamoDB needed
>
> If you only have the Terraform files, this single document covers everything from installing the tools to verifying the deployed stack.

---

## Table of Contents

1. [Architecture overview](#1-architecture-overview)
2. [What gets deployed](#2-what-gets-deployed)
3. [Prerequisites](#3-prerequisites)
4. [Step 1 — Install the required tools](#step-1--install-the-required-tools)
5. [Step 2 — Configure AWS credentials](#step-2--configure-aws-credentials)
6. [Step 3 — Verify access to AWS](#step-3--verify-access-to-aws)
7. [Step 4 — Configure the dev environment files](#step-4--configure-the-dev-environment-files)
8. [Step 5 — Initialize the Terraform backend](#step-5--initialize-the-terraform-backend)
9. [Step 6 — Generate and review the plan](#step-6--generate-and-review-the-plan)
10. [Step 7 — Deploy in phases](#step-7--deploy-in-phases)
11. [Step 8 — Upload the Debezium plugin (MSK Connect prerequisite)](#step-8--upload-the-debezium-plugin-msk-connect-prerequisite)
12. [Step 9 — Post-deployment verification](#step-9--post-deployment-verification)
13. [Operations (after deploy)](#operations-after-deploy)
14. [Troubleshooting](#troubleshooting)
15. [Tearing down the environment](#tearing-down-the-environment)
16. [Support](#support)

---

## 1. Architecture overview

A production-grade Change Data Capture (CDC) pipeline. Source-DB writes are streamed through Debezium → Kafka (MSK) → two consumer targets (Redis cache + PostgreSQL sink DB).

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                    AWS account · region: us-east-2                              │
│                                                                                 │
│   ┌─────────────────────────┐    ┌───────────────────────────┐                 │
│   │  Public subnets (×3)    │    │  Private subnets (×3)     │                 │
│   │                         │    │                           │                 │
│   │  NAT Gateway ──────────┐│    │ • EC2 app servers (×3)    │                 │
│   │  (outbound only)       ││    │ • Aurora Source DB        │                 │
│   │                        ││    │ • Aurora Sink DB          │                 │
│   │  (No EC2 instances     ││    │ • MSK Provisioned Kafka   │                 │
│   │   live here)           ▼│    │ • MSK Connect workers     │                 │
│   │                         │    │ • ElastiCache (Redis)     │                 │
│   │                         │    │ • VPC interface endpoints │                 │
│   └─────────────────────────┘    │   (SSM access)            │                 │
│                                  └───────────────────────────┘                 │
│                                                                                 │
│   CDC data path:                                                                │
│   EC2 → Aurora Source → Debezium (×5) → MSK Kafka → ElastiCache + Aurora Sink   │
└────────────────────────────────────────────────────────────────────────────────┘
```

**Network rules** (per the MoM "no public subnets for core services"):

- EC2 instances have **no public IP**, live in private subnets
- Admin access is via **AWS Systems Manager Session Manager** (no SSH bastion)
- Outbound internet (yum, pip, GitHub) goes via the NAT Gateway
- S3 traffic uses a VPC Gateway endpoint — never crosses the public internet

---

## 2. What gets deployed

| Component | Detail |
|---|---|
| **VPC** | New VPC `10.146.0.0/16` with 3 public + 3 private subnets across `us-east-2a/b/c` |
| **NAT Gateway** | 1 (in public subnet) for outbound internet from private subnets |
| **EC2** | 3 instances — `app-server` (`m6i.2xlarge`) + 2 sink workers (`t3.xlarge`) — all in private subnets |
| **Aurora PostgreSQL Source** | Serverless v2 (0.5–16 ACU, PG 17.7), logical replication enabled |
| **Aurora PostgreSQL Sink** | Serverless v2 (0.5–16 ACU, PG 17.7) |
| **MSK Provisioned** | Kafka 3.9.x, 3 brokers (`kafka.m5.2xlarge`, 1 TB EBS each) across 3 AZs |
| **MSK Connect** | 5 Debezium source connectors (one per table, each with its own replication slot) |
| **ElastiCache** | Serverless Redis, TLS always-on |
| **KMS** | 5 customer-managed keys (S3 / Secrets / Aurora / Redis / EBS) |
| **Security Groups** | Least-privilege, EC2 → MSK, EC2 → Aurora, etc. |
| **VPC endpoints** | SSM × 3 (interface) + S3 (gateway) — all in private subnets |
| **S3 buckets** | 3 — plugins, data-lake, logs (SSE-S3, versioned, public access blocked) |
| **Secrets Manager** | Auto-generated 32-char DB passwords, KMS-encrypted |
| **IAM** | EC2 instance profile + MSK Connect service role |

Total: **~130 AWS resources** created.

**Estimated cost:** ~US$3,000–4,200 / month (MSK + MSK Connect are the largest fixed-cost items).

---

## 3. Prerequisites

| Item | Version | Why |
|---|---|---|
| **Terraform CLI** | ≥ **1.10.0** | Required for native S3 state locking (`use_lockfile`) |
| **AWS CLI** | ≥ 2.13 | Used for AMI lookups, key-pair creation, SSM Session Manager |
| **`session-manager-plugin`** | Latest | Required by `aws ssm start-session` to reach the EC2 instances |
| **`jq`** *(optional)* | Latest | Used by helper scripts to parse JSON plan output |
| **AWS account access** | IAM user / SSO role with admin privileges on the dev account | Must be able to create VPC, EC2, RDS, MSK, MSK Connect, KMS, IAM, Secrets Manager, S3, CloudWatch resources |
| **S3 access to** `tfstate-imss-shared-342448511503-us-west-2` | `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` on `caltech/dev/*` | Where Terraform state and lock file live |

---

## Step 1 — Install the required tools

### macOS (Homebrew)

```bash
brew install terraform awscli jq
brew install --cask session-manager-plugin
```

### Linux (Amazon Linux 2023 / RHEL / Fedora)

```bash
# Terraform
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo dnf install -y terraform

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./aws/install

# jq
sudo dnf install -y jq

# SSM Session Manager plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" \
  -o session-manager-plugin.rpm
sudo dnf install -y ./session-manager-plugin.rpm
```

### Linux (Debian / Ubuntu)

```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# AWS CLI + SSM plugin
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o session-manager-plugin.deb
sudo dpkg -i session-manager-plugin.deb

# jq
sudo apt-get install -y jq
```

### Windows (Git Bash / MINGW64)

```bash
# Easiest path is winget (open a NEW PowerShell window after installing):
winget install Hashicorp.Terraform
winget install Amazon.AWSCLI
winget install Amazon.SessionManagerPlugin
winget install jqlang.jq
```

### Verify

```bash
terraform version             # >= 1.10.0
aws --version                 # >= 2.13
session-manager-plugin        # "session-manager-plugin is installed successfully"
jq --version                  # >= 1.6
```

---

## Step 2 — Configure AWS credentials

Terraform reads credentials from the same chain as the AWS CLI. Pick **one** of the methods below — whichever your team uses.

### Method A — Named profile in `~/.aws/credentials` (simplest)

```bash
aws configure --profile default
# Prompts:
#   AWS Access Key ID     : AKIA...
#   AWS Secret Access Key : ****
#   Default region        : us-east-2          (the region resources will be deployed to)
#   Default output format : json
```

The shipped [envs/dev.backend.hcl](envs/dev.backend.hcl) references `profile = "default"`. If you use a different profile name, update that line or pass `-backend-config="profile=<your-profile>"` at init time (see Step 5).

### Method B — AWS SSO (single sign-on, common in enterprise)

```bash
aws configure sso --profile default
# Prompts walk you through the SSO URL, region, and account selection
# After completion, refresh the session whenever it expires:
aws sso login --profile default
```

### Method C — Environment variables (CI/CD)

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."          # only if using temporary creds
export AWS_REGION="us-east-2"           # default region for AWS CLI calls

# Update backend.hcl to drop the "profile" line so env vars are used:
#   profile = "default"     ← delete
```

### Method D — IAM instance role (if running terraform from an EC2 host)

No configuration needed — the instance role is picked up automatically as long as `profile` is **not** set in the backend or environment. Delete the `profile = "default"` line from [envs/dev.backend.hcl](envs/dev.backend.hcl) and from [envs/dev.tfvars](envs/dev.tfvars).

---

## Step 3 — Verify access to AWS

Three checks — all must pass before continuing.

### 3.1 Verify your identity

```bash
aws sts get-caller-identity --profile default
```

Expected output:

```json
{
  "UserId":  "AIDAEXAMPLE",
  "Account": "342448511503",
  "Arn":     "arn:aws:iam::342448511503:user/your-user"   ← or your SSO role
}
```

### 3.2 Verify access to the state bucket

```bash
aws s3 ls s3://tfstate-imss-shared-342448511503-us-west-2/ \
  --profile default --region us-west-2
```

Should return the contents of the bucket (other projects may share it — that's fine; we use the `caltech/dev/` prefix only).

If you see `AccessDenied`, request your AWS admin to grant your IAM principal the following actions on the bucket:

- `s3:ListBucket` on `arn:aws:s3:::tfstate-imss-shared-342448511503-us-west-2`
- `s3:GetObject` / `PutObject` / `DeleteObject` on `arn:aws:s3:::tfstate-imss-shared-342448511503-us-west-2/caltech/dev/*`

If the bucket uses SSE-KMS, you also need `kms:Decrypt` and `kms:GenerateDataKey` on the bucket's CMK.

### 3.3 Verify deploy region is enabled

```bash
aws ec2 describe-regions --region us-east-2 --profile default \
  --query 'Regions[?RegionName==`us-east-2`].OptInStatus' --output text
# Expected: opt-in-not-required
```

---

## Step 4 — Configure the dev environment files

Two values in [envs/dev.tfvars](envs/dev.tfvars) are region-specific and **must** be set before plan.

### 4.1 Get a fresh `us-east-2` AMI

```bash
aws ec2 describe-images --owners amazon --region us-east-2 --profile default \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
            "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text
# Example: ami-0a1b2c3d4e5f67890
```

Edit [envs/dev.tfvars](envs/dev.tfvars) and replace the placeholder:

```hcl
ec2_ami_id = "ami-0a1b2c3d4e5f67890"   # the value printed above
```

### 4.2 Create the dev EC2 key pair in `us-east-2`

Even though dev uses SSM only, the EC2 resource requires a `key_name`.

```bash
aws ec2 create-key-pair --key-name caltech-dev-keypair \
  --region us-east-2 --profile default \
  --query KeyMaterial --output text > ~/caltech-dev-keypair.pem
chmod 400 ~/caltech-dev-keypair.pem

# Verify
aws ec2 describe-key-pairs --key-name caltech-dev-keypair \
  --region us-east-2 --profile default \
  --query 'KeyPairs[0].KeyName' --output text
```

[envs/dev.tfvars](envs/dev.tfvars) already references `ec2_key_pair_name = "caltech-dev-keypair"` — leave that as is.

### 4.3 Confirm everything else in `envs/dev.tfvars`

Skim the file once. The defaults are sane for a production-grade dev deploy. Three items to verify:

| Variable | Default | Confirm |
|---|---|---|
| `aws_region` | `us-east-2` | matches the region where you want resources |
| `vpc_cidr` | `10.146.0.0/16` | does not collide with any existing VPC in your account |
| `ec2_in_private_subnet` | `true` | per MoM — leave `true` |

---

## Step 5 — Initialize the Terraform backend

```bash
cd prod-stack

# Clean any leftover backend cache (safe — does not touch S3)
rm -rf .terraform .terraform.lock.hcl

# Initialize against the dev backend
terraform init -backend-config=envs/dev.backend.hcl
```

If your AWS profile is **not** `default`, override at init time:

```bash
terraform init \
  -backend-config=envs/dev.backend.hcl \
  -backend-config="profile=<your-profile>"
```

Successful output ends with:

```
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

If you see `AccessDenied` here, recheck Step 3.2 (state bucket access).

---

## Step 6 — Generate and review the plan

```bash
terraform plan -var-file=envs/dev.tfvars -out=dev.tfplan
```

### What the plan output should show

| Check | Expected |
|---|---|
| Summary line at the bottom | `Plan: ~120-140 to add, 0 to change, 0 to destroy.` |
| Destroys | **Must be 0** (this is a fresh dev deploy) |
| `module.vpc[0].aws_vpc.this` → `cidr_block` | `10.146.0.0/16` |
| `module.ec2.aws_instance.app` → `subnet_id` | a **private** subnet (not public) |
| `module.ec2_pg_sink.aws_instance.app` → `subnet_id` | a **private** subnet |
| `module.ec2_redis_sink.aws_instance.app` → `subnet_id` | a **private** subnet |
| `module.vpc_endpoints.aws_vpc_endpoint.ssm[*]` | 3 SSM interface endpoints in private subnets |

### Save a human-readable copy for review

```bash
terraform show -no-color dev.tfplan > dev-plan.txt
grep -E "^Plan:|will be created|will be destroyed" dev-plan.txt | tail -20
```

If destroys ≠ 0 or you see a subnet pointing at a public subnet — **stop** and re-check Step 4.

### Plan failure: `Error: no matching MSK Connect Custom Plugin found`

This is **expected on a brand-new dev account**. The MSK Connect module looks up a pre-existing custom plugin that hasn't been registered yet. Solution:

- For now, generate a partial plan that skips the connector module (see Step 7 phasing).
- The plugin is created in [Step 8](#step-8--upload-the-debezium-plugin-msk-connect-prerequisite), after MSK is up and the plugins S3 bucket exists.

---

## Step 7 — Deploy in phases

For a fresh environment, deploy in phases — each phase has a clear "done" signal and is independently revertible. Skip to the "single shot" at the bottom if you prefer.

### Phase 0 — VPC (3 min)

```bash
terraform apply -var-file=envs/dev.tfvars -target=module.vpc
```

**Hand-off:** VPC + subnets + IGW + NAT Gateway created. Verify:

```bash
terraform output vpc_id public_subnet_ids private_subnet_ids
```

### Phase 1 — Foundation (~7 min)

```bash
terraform apply -var-file=envs/dev.tfvars \
  -target=module.kms \
  -target=module.security_groups \
  -target=module.vpc_endpoints \
  -target=module.s3 \
  -target=module.secrets \
  -target=module.iam
```

**Hand-off:** KMS keys, security groups, S3 buckets, Secrets Manager secrets, and IAM roles ready.

### Phase 2 — EC2 instances (~3 min)

```bash
terraform apply -var-file=envs/dev.tfvars \
  -target=module.ec2 \
  -target=module.ec2_pg_sink \
  -target=module.ec2_redis_sink
```

**Hand-off:** 3 EC2 instances running in private subnets. Verify:

```bash
terraform output ec2_instance_id ec2_pg_sink_instance_id ec2_redis_sink_instance_id
aws ec2 describe-instances --instance-ids $(terraform output -raw ec2_instance_id) \
  --region us-east-2 --profile default \
  --query 'Reservations[].Instances[].[PublicIpAddress,SubnetId,State.Name]' --output table
# PublicIpAddress should be None (private subnet)
```

### Phase 3 — Aurora Source DB (~10–15 min)

```bash
terraform apply -var-file=envs/dev.tfvars -target=module.aurora_source
```

**Hand-off:** Source DB online with logical replication enabled. Endpoint:

```bash
terraform output aurora_source_endpoint
```

### Phase 4a — MSK Provisioned cluster (~30–40 min — the long pole)

```bash
terraform apply -var-file=envs/dev.tfvars -target=module.msk
```

**Hand-off:** Kafka cluster ready. Note the bootstrap brokers:

```bash
terraform output msk_bootstrap_brokers
```

### → Now do [Step 8](#step-8--upload-the-debezium-plugin-msk-connect-prerequisite) — register the Debezium plugin

### Phase 4b — MSK Connect connectors (~10–15 min)

After Step 8 completes:

```bash
terraform apply -var-file=envs/dev.tfvars -target=module.msk_connect
```

**Hand-off:** 5 Debezium source connectors live, CDC flowing from Aurora Source → MSK.

### Phase 5 — Consumer targets (~10–20 min)

```bash
terraform apply -var-file=envs/dev.tfvars \
  -target=module.elasticache \
  -target=module.aurora_sink
```

**Hand-off:** Redis cache and Aurora Sink DB ready as consumer targets.

### Final pass (validates the whole stack)

```bash
terraform apply -var-file=envs/dev.tfvars
```

**Expected output:** `No changes. Your infrastructure matches the configuration.`

### Single-shot alternative

If you'd rather deploy everything in one command:

```bash
# Run Step 8 (plugin upload) FIRST, then:
terraform apply dev.tfplan
```

Total wall-clock time: **~1.5–2 hours** (MSK is the long pole).

---

## Step 8 — Upload the Debezium plugin (MSK Connect prerequisite)

The MSK Connect module references a custom plugin by **name**. The plugin must be registered with MSK Connect before that module can plan or apply. This is a one-time step per AWS region.

### 8.1 Download the Debezium PostgreSQL connector ZIP locally

```bash
mkdir -p ~/plugins && cd ~/plugins

# Version pinned in envs/dev.tfvars: plugins/debezium-debezium-connector-postgresql-3.2.6-1.zip
curl -L -o debezium-debezium-connector-postgresql-3.2.6-1.zip \
  "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/3.2.6.Final/debezium-connector-postgres-3.2.6.Final-plugin.zip"

ls -lh debezium-debezium-connector-postgresql-3.2.6-1.zip
# Should be ~25–30 MB
```

### 8.2 Upload to the dev plugins bucket

The plugins bucket is created by Phase 1. Get its name from Terraform:

```bash
cd <project-root>/prod-stack
PLUGIN_BUCKET=$(terraform output -raw s3_plugins_bucket)
echo "Uploading to: $PLUGIN_BUCKET"

aws s3 cp ~/plugins/debezium-debezium-connector-postgresql-3.2.6-1.zip \
  s3://${PLUGIN_BUCKET}/plugins/debezium-debezium-connector-postgresql-3.2.6-1.zip \
  --region us-east-2 --profile default
```

### 8.3 Register the plugin with MSK Connect

```bash
aws kafkaconnect create-custom-plugin \
  --name caltech-dev-debezium-postgresql-source-connector-plugin \
  --content-type ZIP \
  --location "{\"s3Location\":{\"bucketArn\":\"arn:aws:s3:::${PLUGIN_BUCKET}\",\"fileKey\":\"plugins/debezium-debezium-connector-postgresql-3.2.6-1.zip\"}}" \
  --region us-east-2 --profile default
```

### 8.4 Wait for the plugin to become ACTIVE (~30–60 seconds)

```bash
aws kafkaconnect list-custom-plugins --region us-east-2 --profile default \
  --query 'customPlugins[?name==`caltech-dev-debezium-postgresql-source-connector-plugin`].{Name:name,State:customPluginState}' \
  --output table
```

Wait until `State` shows `ACTIVE`. Now Phase 4b in Step 7 can run.

---

## Step 9 — Post-deployment verification

### 9.1 Confirm EC2 has no public IP

```bash
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --region us-east-2 --profile default \
  --query 'Reservations[].Instances[].[PublicIpAddress,PrivateIpAddress,SubnetId]' \
  --output table
# PublicIpAddress should be None / empty
```

### 9.2 Log in via SSM Session Manager (no SSH key)

```bash
aws ssm start-session --target $INSTANCE_ID --region us-east-2 --profile default

# Inside the session:
curl -I https://www.amazon.com         # confirm outbound internet via NAT — expect HTTP/2 200
exit                                   # leave the session
```

### 9.3 Confirm the Aurora Source DB is reachable

```bash
SECRET_ARN=$(terraform output -raw aurora_source_secret_arn)
SOURCE_PW=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region us-east-2 --profile default \
  --query SecretString --output text | jq -r '.password')

# From the EC2 app server (after SSM session):
psql -h $(terraform output -raw aurora_source_endpoint) \
     -U dbadmin -d sourcedb -W   # paste $SOURCE_PW when prompted
```

### 9.4 Confirm MSK Connect connectors are running

```bash
aws kafkaconnect list-connectors --region us-east-2 --profile default \
  --query "connectors[?starts_with(connectorName, 'caltech-dev')].{Name:connectorName,State:connectorState}" \
  --output table
# All 5 should show State: RUNNING
```

### 9.5 Confirm Redis endpoint resolves

```bash
terraform output redis_endpoint redis_port
```

---

## Operations (after deploy)

### Connect to any EC2 instance

```bash
terraform output ssm_connect_command             # app server
terraform output ssm_connect_command_pg_sink     # PG sink worker
terraform output ssm_connect_command_redis_sink  # Redis sink worker
```

Then run the printed command — e.g.:

```bash
aws ssm start-session --target i-0xxxx --region us-east-2 --profile default
```

### Get a DB password from Secrets Manager

```bash
SECRET_ARN=$(terraform output -raw aurora_source_secret_arn)
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" \
  --region us-east-2 --profile default --query SecretString --output text | jq -r '.password'
```

### List all Terraform outputs

```bash
terraform output
```

### Re-plan / re-apply after editing the code

```bash
terraform plan -var-file=envs/dev.tfvars -out=dev.tfplan
terraform apply dev.tfplan
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform init` → `AccessDenied` on S3 | Caller can't read/write the state bucket | Grant the IAM principal `s3:GetObject/PutObject/DeleteObject/ListBucket` on `tfstate-imss-shared-342448511503-us-west-2/caltech/dev/*` |
| `terraform init` → `Backend configuration changed` | Stale `.terraform/` cache from a different env | `rm -rf .terraform .terraform.lock.hcl` then re-run `terraform init` |
| `Error: no matching MSK Connect Custom Plugin found` | Plugin not registered yet in this region | Complete [Step 8](#step-8--upload-the-debezium-plugin-msk-connect-prerequisite) before applying `module.msk_connect` |
| `InvalidAMIID.NotFound` | Placeholder AMI ID in tfvars | Repeat [Step 4.1](#41-get-a-fresh-us-east-2-ami) and update `ec2_ami_id` |
| `InvalidKeyPair.NotFound` | Key pair missing in us-east-2 | Repeat [Step 4.2](#42-create-the-dev-ec2-key-pair-in-us-east-2) |
| Plan shows `X to destroy` on a fresh deploy | Wrong backend or wrong tfvars active | `rm -rf .terraform*` then re-init with the **dev** backend explicitly |
| `Lock Info: ID: ...` then hangs | Stale lock file from a crashed apply | `terraform force-unlock <lock-id>` |
| `UnauthorizedOperation` on `kafkaconnect:*` | Caller is missing MSK Connect permissions | Add `AWSManagedMSKConnectFullAccess` (or scoped equivalent) to the IAM principal |
| SSM `TargetNotConnected` | SSM endpoints not reachable from EC2, or instance still booting | Wait 2 minutes after launch, then retry. If persistent, check `module.vpc_endpoints` deployed successfully |
| MSK takes > 60 min to create | Capacity issue in the target AZ | Edit `availability_zones` in `envs/dev.tfvars` to a different combo and re-plan |

---

## Tearing down the environment

```bash
# 1. (If deletion protection is on) edit envs/dev.tfvars:
#      aurora_deletion_protection = false
#      aurora_skip_final_snapshot = true     # set false to keep a final snapshot
terraform apply -var-file=envs/dev.tfvars

# 2. Destroy MSK Connect connectors first (they hold replication slots open)
terraform destroy -var-file=envs/dev.tfvars -target=module.msk_connect

# 3. Destroy everything else
terraform destroy -var-file=envs/dev.tfvars

# 4. (Optional) Deregister the custom plugin
aws kafkaconnect delete-custom-plugin \
  --custom-plugin-arn $(aws kafkaconnect list-custom-plugins --region us-east-2 \
      --query 'customPlugins[?name==`caltech-dev-debezium-postgresql-source-connector-plugin`].customPluginArn|[0]' \
      --output text --profile default) \
  --region us-east-2 --profile default
```

The state file at `s3://tfstate-imss-shared-342448511503-us-west-2/caltech/dev/terraform.tfstate` will still exist after destroy (it just contains an empty resource set). Delete it manually only if you want to fully reset the env:

```bash
aws s3 rm s3://tfstate-imss-shared-342448511503-us-west-2/caltech/dev/terraform.tfstate \
  --region us-west-2 --profile default
```

---

## Support

For issues during deployment, contact the **Platform Team — panicleTech** with:

- Environment: `dev`
- Region: `us-east-2`
- Account: `342448511503`
- The exact `terraform` command you ran
- Full error output (`terraform plan` / `apply` log)

Reference files in this repo:

- [README.md](README.md) — top-level overview + environment matrix
- [DOCUMENTATION.md](DOCUMENTATION.md) — full operational reference for the stack
- [envs/dev.tfvars](envs/dev.tfvars) — dev environment variables
- [envs/dev.backend.hcl](envs/dev.backend.hcl) — dev S3 backend config
- [scripts/init.sh](scripts/init.sh) — automated bootstrap (optional alternative to manual init)
- [scripts/generate-plan-report.sh](scripts/generate-plan-report.sh) — generates a client-shareable plan bundle
