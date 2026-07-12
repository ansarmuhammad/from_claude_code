# Terraform - CI/CD Architect Exam Prep Infrastructure

This directory provisions the AWS infrastructure that the GitHub Actions
pipeline (`.github/workflows/ci-cd-pipeline.yml`) deploys application
manifests onto via `kubectl apply -k kubernetes/overlays/<env>/`. It is
scaffolding for hands-on Terraform/CI-CD practice, not a real production
deployment - there are no live cloud credentials wired to it.

## What gets provisioned

For each environment (`dev`, `staging`, `production`) this stack creates:

- **Networking** - a VPC with public + private subnets across multiple AZs,
  an Internet Gateway, NAT Gateway(s), and route tables.
- **EKS** - the Kubernetes cluster the pipeline's `kubectl apply -k` commands
  target, a managed node group, IAM roles for the control plane and nodes,
  and an OIDC provider for IRSA (IAM Roles for Service Accounts).
- **RDS (PostgreSQL)** - the managed equivalent of the `postgres` container
  in `docker-compose.yml`, with a generated master password stored in
  Secrets Manager (never rendered as a plaintext Terraform output).
- **ElastiCache (Redis)** - the managed equivalent of the `redis` container,
  used for the Celery broker/result backend and app-level caching.
- **ECR** - one container repository per service (`api-service`,
  `web-frontend`, `worker-service`) with image scanning on push and a
  lifecycle policy that expires old/untagged images, matching the
  `build` job's `matrix.service` in the CI/CD workflow.

## Layout

```
terraform/
├── modules/
│   ├── networking/    # VPC, subnets, IGW, NAT, route tables
│   ├── eks/            # EKS cluster, managed node group, IAM, OIDC/IRSA
│   ├── rds/             # PostgreSQL instance, subnet group, SG, param group
│   ├── elasticache/      # Redis replication group, subnet group, SG
│   └── ecr/               # One repo per service + lifecycle policy
└── environments/
    ├── dev/            # Small/cheap, single shared NAT, single-AZ data stores
    ├── staging/         # Moderate sizing, Multi-AZ data stores
    └── production/       # 3 AZs, full HA, deletion_protection = true
```

Each module is self-contained (`main.tf`, `variables.tf`, `outputs.tf`,
`versions.tf` pinning `aws ~> 5.0`) and is wired together per-environment in
that environment's `main.tf`. Environments do not share Terraform state -
each has its own S3 backend key, so `dev`/`staging`/`production` can be
planned and applied independently.

### Environment sizing at a glance

| | dev | staging | production |
|---|---|---|---|
| AZs | 2 (min. required by EKS) | 2 | 3 |
| NAT Gateways | 1 shared | 1 per AZ | 1 per AZ |
| EKS nodes | `t3.medium` x 2 | `m5.large` x 3 | `m5.xlarge` x 4 |
| RDS | `db.t3.micro`, single-AZ | `db.t3.medium`, Multi-AZ | `db.r6g.large`, Multi-AZ, `deletion_protection = true` |
| Redis | 1 node, no failover | 2 nodes, automatic failover | 3 nodes, automatic failover, in-transit encryption |
| ECR tags | mutable | immutable | immutable |

> Note on "dev = single-AZ": EKS requires cluster subnets to span at least
> two Availability Zones even in dev, so the cost savings in `dev` come from
> a single shared NAT Gateway and non-HA RDS/Redis, not from a literal
> single-AZ VPC.

## Prerequisite: bootstrap the remote state backend (once, out-of-band)

Each environment's `backend.tf` points at an S3 bucket and DynamoDB lock
table with **placeholder names** (`cicd-architect-exam-tfstate-REPLACE_ME`,
`cicd-architect-exam-tf-locks`). Terraform cannot create its own backend, so
these must exist *before* the first `terraform init`. Create them once,
out-of-band (e.g. with the AWS CLI, or a bootstrap Terraform config kept
outside this repo's state):

```bash
aws s3api create-bucket \
  --bucket cicd-architect-exam-tfstate-<your-unique-suffix> \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket cicd-architect-exam-tfstate-<your-unique-suffix> \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket cicd-architect-exam-tfstate-<your-unique-suffix> \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name cicd-architect-exam-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

Then update the `bucket` (and `dynamodb_table`, if you changed it) value in
each `terraform/environments/*/backend.tf` to match.

## Usage

Run everything from inside the specific environment directory - each has
its own state and variable values.

```bash
cd terraform/environments/dev      # or staging / production

terraform init                      # downloads providers, configures the S3 backend
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

`terraform.tfvars` in each environment already carries example values, so
`plan`/`apply` work without extra flags too (Terraform auto-loads
`terraform.tfvars`); the `-var-file` above is shown for clarity.

To tear an environment down:

```bash
terraform destroy -var-file=terraform.tfvars
```

Production has `deletion_protection = true` on RDS, so the database must be
explicitly modified (or the flag flipped and re-applied) before a `destroy`
will succeed - this is intentional friction to prevent accidental data loss.

### Validating without cloud credentials

Since this is exam-prep scaffolding, you can sanity-check the HCL without
any real AWS account:

```bash
cd terraform/environments/dev
terraform init -backend=false   # skip backend, no S3 bucket needed
terraform validate
```

Repeat for `staging` and `production`. `terraform fmt -recursive` from the
`terraform/` directory keeps formatting consistent across all modules and
environments.
