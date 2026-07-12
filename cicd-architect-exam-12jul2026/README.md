# CI/CD Pipeline Practice Project

## Claude Certified Architect Exam Preparation

A complete, runnable CI/CD reference implementation: three microservices, a
GitHub Actions pipeline, Kustomize-based Kubernetes manifests with a
blue/green production overlay, Terraform IaC for the underlying AWS
infrastructure, a Prometheus/Grafana observability stack, and a full test
pyramid (unit → integration → e2e → performance). Built as a hands-on study
environment for CI/CD and cloud architecture exam prep — start with
[`docs/exam-prep-notes.md`](docs/exam-prep-notes.md).

**Repo**: https://github.com/ansarmuhammad/from_claude_code/tree/mlx/cicd-architect-exam-12jul2026

## Project Structure

```
cicd-architect-exam-12jul2026/
├── README.md
├── docker-compose.yml            # Full local dev stack (all services + observability)
├── apps/
│   ├── api-service/              # FastAPI REST API (Task CRUD), Prometheus metrics
│   ├── worker-service/           # Celery background worker (Redis broker)
│   └── web-frontend/             # React + TypeScript SPA
├── .github/workflows/
│   └── ci-cd-pipeline.yml        # code-quality -> unit -> build -> scan -> integration
│                                  # -> deploy-dev -> deploy-staging -> deploy-production -> perf
├── docker/
│   ├── Dockerfile.api-service    # Multi-stage, non-root
│   ├── Dockerfile.worker-service
│   ├── Dockerfile.web-frontend   # Node build -> nginx serve
│   ├── nginx.conf
│   └── docker-compose.test.yml   # Slim stack used by CI's integration-tests job
├── kubernetes/
│   ├── base/                     # Deployments, Services, ConfigMap, Secret, HPA
│   └── overlays/
│       ├── dev/                  # namespace: development, 1 replica
│       ├── staging/               # namespace: staging, 2 replicas
│       └── production/
│           ├── blue/              # namespace: production, version=blue
│           └── green/             # namespace: production, version=green
├── terraform/
│   ├── modules/                  # networking (VPC), eks, rds, elasticache, ecr
│   └── environments/             # dev, staging, production (own backend + tfvars)
├── monitoring/
│   ├── prometheus.yml            # scrapes api-service:8000, worker-service:9100
│   ├── alerts.yml                # HighErrorRate, HighLatency, ServiceDown, ...
│   └── grafana/                  # datasource + dashboard provisioning
├── scripts/
│   ├── build.sh                  # Build all 3 service images
│   ├── deploy.sh                 # Deploy to dev/staging/production (blue/green aware)
│   ├── rollback.sh               # kubectl rollout undo, confirmation-gated for prod
│   ├── setup-local-env.sh        # Bootstrap .env + docker-compose up
│   └── run-tests.sh              # Unit (+ --integration/--e2e/--perf flags)
├── tests/
│   ├── integration/              # pytest + httpx against a running api-service
│   ├── e2e/                      # Playwright against web-frontend
│   └── performance/              # k6 load test
└── docs/
    ├── architecture.md           # System design, service boundaries, data flow
    ├── ci-cd-pipeline.md         # Stage-by-stage walkthrough of the GitHub Actions pipeline
    ├── exam-prep-notes.md        # Study guide: concepts demonstrated here <-> exam topics
    └── runbook.md                # Incident scenarios: detection, diagnosis, remediation
```

## Architecture Overview

### Microservices
- **api-service** — FastAPI REST API exposing `Task` CRUD at `/api/v1/tasks`, a `/health`
  endpoint, and Prometheus metrics at `/metrics` (request count + latency histogram).
- **worker-service** — Celery worker consuming from Redis, with sample background
  tasks (`process_item`, `send_notification`, `generate_report`) and its own
  Prometheus metrics server on port 9100.
- **web-frontend** — React/TypeScript SPA that lists/creates tasks against api-service
  and surfaces a health indicator.

Data stores: PostgreSQL (task persistence contract — the demo app currently
keeps tasks in memory, see `docs/architecture.md` for the caveat), Redis
(Celery broker/result backend). Jaeger is wired into `docker-compose.yml`
for distributed tracing.

### CI/CD Pipeline (`.github/workflows/ci-cd-pipeline.yml`)
1. **Code quality** — Black, Flake8, MyPy, Bandit, Safety
2. **Unit tests** — pytest matrix across api-service/worker-service, coverage uploaded to Codecov
3. **Build** — multi-stage Docker builds for all 3 services, pushed to GHCR
4. **Container scan** — Trivy, SARIF results to GitHub Security
5. **Integration tests** — `docker-compose.test.yml` stack + pytest
6. **Deploy to dev** — `kubectl apply -k kubernetes/overlays/dev/` (on `develop`)
7. **Deploy to staging** — rolling image update + Playwright e2e (on `main`)
8. **Deploy to production** — blue/green cutover via Service selector patch
9. **Performance test** — k6 load test against staging

See `docs/ci-cd-pipeline.md` for the reasoning behind each stage, including
an honest look at where the pipeline's comments overstate what it actually
does (e.g. the "canary" label vs. its real rolling-update mechanism).

### Technologies Used
- **CI/CD**: GitHub Actions
- **Containers**: Docker, Kubernetes, Kustomize
- **IaC**: Terraform (AWS: VPC, EKS, RDS, ElastiCache, ECR)
- **Testing**: pytest, Jest/React Testing Library, Playwright, k6
- **Security**: Bandit, Safety, Trivy
- **Monitoring**: Prometheus, Grafana, Jaeger

## Quick Start

### Prerequisites
- Docker Desktop
- kubectl + a Kubernetes cluster (kind/minikube/EKS) for the K8s workflow
- Terraform 1.5+ for the IaC workflow
- Python 3.11+, Node.js 18+ (only needed if running services outside Docker)

### Local Development
```bash
# One-shot bootstrap: checks tooling, creates .env, starts the full stack
./scripts/setup-local-env.sh

# ...or manually:
docker-compose up -d
# api-service   -> http://localhost:8000  (docs at /docs, metrics at /metrics)
# web-frontend  -> http://localhost:3000
# grafana       -> http://localhost:3001  (admin/admin)
# prometheus    -> http://localhost:9090
# jaeger UI     -> http://localhost:16686

# Run tests
./scripts/run-tests.sh              # unit tests only
./scripts/run-tests.sh --all        # + integration, e2e, performance
```

### Kubernetes
```bash
./scripts/deploy.sh dev
./scripts/deploy.sh staging
./scripts/deploy.sh production      # runs the blue/green cutover sequence
./scripts/rollback.sh production    # kubectl rollout undo, confirmation-gated
```

### Terraform
```bash
cd terraform/environments/dev
terraform init      # see terraform/README.md for the one-time S3+DynamoDB backend setup
terraform plan
terraform apply
```

## Study Resources
- [`docs/architecture.md`](docs/architecture.md) — system design and service boundaries
- [`docs/ci-cd-pipeline.md`](docs/ci-cd-pipeline.md) — pipeline stage-by-stage walkthrough
- [`docs/exam-prep-notes.md`](docs/exam-prep-notes.md) — concepts demonstrated here mapped to exam topics (deployment strategies, IaC, container security, observability, GitOps vs. push-based CD, secrets management), including known gaps and bugs found and fixed along the way
- [`docs/runbook.md`](docs/runbook.md) — incident response scenarios
- [`terraform/README.md`](terraform/README.md) — module layout and backend bootstrap
- [`tests/README.md`](tests/README.md) — how to run each layer of the test pyramid
