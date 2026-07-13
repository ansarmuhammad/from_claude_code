# Exam Prep Notes: Mapping This Repo to CI/CD / Cloud Architecture Concepts

This is the study-guide doc. Each section takes a concept a "Claude
Certified Architect"-style exam would expect you to know, points at where
(if anywhere) this repo demonstrates it, and is explicit about what's
real vs. what's a shortcut taken for the sake of having a runnable
scaffold. Treat the "honest assessment" callouts as seriously as the
concept explanations - a study tool that just says "great job" on
everything teaches you nothing you can defend under exam questioning.

---

## 1. Deployment strategies

### Blue/Green (what this repo actually implements)
`deploy-production` in `.github/workflows/ci-cd-pipeline.yml` runs two
full, independently-addressable pod sets (`version=blue`,
`version=green`) and cuts traffic over by patching the Service selector
(`kubectl patch service api-service -n production -p
'{"spec":{"selector":{"version":"green"}}}'`).

- **Mechanism**: 100% of traffic moves atomically at the Service-selector
  level. Both versions run simultaneously (2x pod capacity during the
  switch), and rollback is, in principle, "patch the selector back" -
  fast, and doesn't require the old ReplicaSet to still be scaling back
  up (it never scaled down).
- **When to use it**: when you need near-instant rollback and can afford
  2x capacity for the cutover window; when you want an all-or-nothing
  cutover rather than gradual exposure.
- **Honest gap in this repo**: the "verification" between switching
  traffic and refreshing blue is `sleep 30` - a fixed pause, not a
  health/metrics check. A real blue/green pipeline gates progression (and
  gates *staying* on green) on actual signals: error rate, latency,
  synthetic transactions - see `docs/ci-cd-pipeline.md` section 8 for the
  detailed critique. Know this distinction for the exam: **"blue/green"
  describes the traffic-cutover mechanism; it says nothing about whether
  you verify before/after cutover.** This repo has the mechanism but not
  the verification discipline a production system needs.

### Canary (contrast - not actually implemented here, despite the comment)
`deploy-staging`'s YAML comment says "Deploy to Kubernetes with Canary,"
but the commands are a plain `kubectl set image` rolling update - no
traffic splitting, no gradual percentage ramp, no automated analysis.

- **Real canary mechanism**: route a small percentage of traffic (e.g.
  5%) to the new version, compare metrics against the baseline (old
  version), and progressively increase the percentage only if metrics
  stay healthy - typically via a service mesh (Istio, Linkerd), an
  ingress controller with weighted routing, or a purpose-built tool
  (Argo Rollouts, Flagger).
- **Canary vs. blue/green, the exam-relevant distinction**: canary
  exposes a *subset* of real users to the new version and compares against
  a control group live; blue/green exposes *all* users to the new version
  at once, after readiness checks, but with no live A/B comparison.
  Canary catches regressions with less blast radius but needs traffic
  splitting infra; blue/green needs 2x capacity but is operationally
  simpler and gives an instant full rollback path.
- **Lesson for the exam**: a comment or job name calling something
  "canary" doesn't make it one - always check what the underlying
  primitive actually does (traffic splitting? weighted routing?
  metrics-gated promotion?) rather than trusting labels.

### Rolling update (used in `deploy-dev` and, in effect, `deploy-staging`)
`kubectl apply -k kubernetes/overlays/dev/` and
`kubectl set image deployment/api-service ...` both rely on Kubernetes'
default Deployment rolling-update strategy: replace pods incrementally,
respecting `maxUnavailable`/`maxSurge`, no traffic splitting concept at
all (Kubernetes just adds new pods to the Service's endpoint list as they
become Ready and removes old ones as they terminate).

- **Trade-off**: no extra capacity needed, but rollback isn't instant
  (Kubernetes must roll pods back the same incremental way), and there's
  a window where old and new versions both receive traffic
  indiscriminately (unlike canary's controlled percentage).

---

## 2. Infrastructure as Code principles

The README documents `terraform/modules/` and `terraform/environments/`
as the intended IaC layout (being built out alongside this doc - treat
the following as the *principles* to look for/apply there, not a
description of file contents already reviewed):

- **Module/environment separation**: reusable `modules/` (e.g. a
  "kubernetes cluster" module, a "VPC" module) parameterized and then
  *instantiated per environment* under `environments/{dev,staging,production}/`
  with environment-specific variable values (instance sizes, replica
  counts, domain names). This is the IaC equivalent of the kustomize
  `base/` + `overlays/{dev,staging,production}/` split already visible
  under `kubernetes/` - same principle (one source of truth, environment-
  specific overrides), applied at the infrastructure-provisioning layer
  instead of the manifest layer.
- **Remote state**: Terraform state must live somewhere shared and
  durable (S3 + DynamoDB lock table, Terraform Cloud, GCS with native
  locking, Azure Blob + Cosmos DB lease, etc.) - never as a local
  `terraform.tfstate` file, which breaks team collaboration and is a
  single point of data loss.
- **State locking**: prevents two people (or two CI runs) from applying
  concurrently and corrupting state or double-provisioning resources.
  This matters even more in a CI/CD context than for a solo developer:
  a pipeline that can trigger concurrent `terraform apply` runs (e.g. two
  PRs merging close together) needs locking to avoid a race.
- **Drift detection**: `terraform plan` in CI on a schedule (or before
  every apply) to catch out-of-band changes (someone `kubectl edit`-ing a
  resource Terraform also manages, or a console click) before they cause
  a surprising diff on the next real apply.
- **Exam framing**: IaC's value isn't "no more manual clicking" so much
  as *reviewable, versioned, reproducible* infrastructure changes - the
  same PR-review/CI gate discipline this repo applies to application code
  (via `code-quality`, `unit-tests`, etc.) should apply to
  infrastructure changes too (`terraform plan` output as a PR comment,
  `terraform apply` gated the same way `deploy-production` is).

---

## 3. Container security

Checked directly against `docker/Dockerfile.api-service` and
`docker/Dockerfile.worker-service` in this repo (not assumed):

| Practice | Present here? | Detail |
|---|---|---|
| Multi-stage build | **Yes** | Both Dockerfiles have a `builder` stage (installs `gcc`/`g++`, builds a venv) and a slim runtime stage that only copies `/opt/venv` and the app - build tools never ship in the final image. |
| Non-root user | **Yes** | Both create `appuser` (`groupadd -r appuser && useradd -r -g appuser appuser`) and `USER appuser` before `CMD`. `COPY --chown=appuser:appuser` also avoids a root-owned app directory. |
| Trivy scanning | **Yes, in CI** | `container-scan` job scans every built image, severity-filtered to `CRITICAL,HIGH`, results uploaded as SARIF to GitHub Security. |
| Minimal base image | **Partially** | `python:3.11-slim`, not a distroless or Alpine-based image - smaller than the full `python:3.11` image, but not as minimal as it could be (distroless has no shell/package manager at all, further reducing attack surface). |
| Pinned base image digest | **No** | `FROM python:3.11-slim` (and `as builder`) is a mutable tag, not pinned to a digest (`@sha256:...`). A rebuild weeks later can silently pull a different underlying image. |

**Honest assessment - this repo does better here than it might first
appear**: it would have been easy to assume a "practice project" skips
multi-stage builds and non-root users, but both Dockerfiles already do
both correctly. The real gaps are more subtle: the scan may not actually
*gate* the pipeline (see `docs/ci-cd-pipeline.md` section 4), and base
images aren't pinned to digests.

One bug that *was* caught during a review pass and is worth knowing about
for the exam, even though it's now fixed: `Dockerfile.api-service`'s
`HEALTHCHECK` originally ran
`python -c "import requests; requests.get(...)"`, but `requests` was
never listed in `apps/api-service/requirements.txt` (only `httpx` was).
That would have raised `ModuleNotFoundError` on every check and reported
the container unhealthy regardless of whether the app itself was fine -
a good example of how a Dockerfile can look secure/correct on a
read-through while still shipping a broken health check. It's been fixed
to use `urllib.request` (stdlib, no extra dependency needed) instead.
Always check that HEALTHCHECK commands only use dependencies actually
installed in the *runtime* stage.

**What's genuinely missing for production-grade container security**
(not present here, and not necessarily expected in a scaffold, but know
it for the exam):
- Image signing/verification (Sigstore/cosign) and admission-time policy
  enforcement (e.g. only run images signed by CI).
- SBOM generation (`syft`, or Trivy's own SBOM mode) attached to each
  build as an artifact for supply-chain auditing.
- Read-only root filesystem (`securityContext.readOnlyRootFilesystem`)
  and dropped Linux capabilities at the Kubernetes Pod level - the
  Dockerfile's `USER appuser` is necessary but not sufficient; the
  Kubernetes `securityContext` needs equivalent hardening (this repo's
  `kubernetes/` manifests should be checked for this once available).

---

## 4. Observability: the four golden signals

`docker-compose.yml` wires up Prometheus + Grafana (+ Jaeger for
tracing), and `apps/api-service/app.py` / `apps/worker-service/worker.py`
both expose Prometheus metrics.

| Golden signal | Where it's covered here | Gap |
|---|---|---|
| **Latency** | `api_request_duration_seconds` (Histogram, api-service); `worker_task_duration_seconds` (Histogram, worker-service) | `api_request_duration_seconds` was originally declared but never `.observe()`'d anywhere in `app.py` - a real instance of "declaring a metric isn't the same as instrumenting the code path that should update it." It's since been fixed with an `@app.middleware("http")` handler that times every request and observes the duration. `worker_task_duration_seconds` was correctly wired from the start via Celery's `task_prerun`/`task_success` signals. Still worth a habit for the exam: whenever you see a `Histogram`/`Counter` declared, grep for `.observe(`/`.inc(` to confirm it's actually reachable from a real code path, not just declared. |
| **Traffic** | `api_requests_total` Counter, labeled by method/endpoint/status, now incremented via a single `@app.middleware("http")` handler covering every route | Two real bugs were found and fixed here. First, the counter was originally only incremented inside the Task CRUD handlers - hitting `/health`, `/`, or the new demo endpoints never counted at all, even though the doc previously (incorrectly) said it was "used per-endpoint". Second, and more seriously: the original per-handler calls labeled `endpoint` with the *resolved* path (e.g. `/api/v1/tasks/28f1...-uuid`), so every distinct task id became its own permanent Prometheus time series - unbounded cardinality growth, a classic and costly production mistake. Fixed by labeling with the route's *path template* (`request.scope["route"].path`, e.g. `/api/v1/tasks/{task_id}`) instead. |
| **Errors** | Implicit in `api_requests_total`'s `status` label (e.g. `404`) and `worker_tasks_total`'s `status="failure"` via Celery signals | No explicit error-rate *alert rule* is shown anywhere in this repo yet - a raw counter isn't an alert; someone still has to define "error rate > X% over Y minutes" in Prometheus alerting rules / Grafana alerting. |
| **Saturation** | Not directly instrumented in application code | This is the weakest of the four here - queue depth (Celery/Redis), DB connection pool usage, and CPU/memory saturation would typically come from Redis/Postgres exporters and cAdvisor/kube-state-metrics rather than from the app's own `/metrics`, and none of those exporters are wired into `docker-compose.yml` as of this doc. |

**Exam framing**: the four golden signals (Google SRE book: latency,
traffic, errors, saturation) are a *minimum checklist* for whether a
service is observable enough to run an on-call rotation against. This
repo demonstrates the instrumentation pattern (Prometheus client
libraries, `/metrics` endpoints, Prometheus scraping, Grafana
visualization) but do not assume "Prometheus + Grafana are in
docker-compose.yml" automatically means all four signals are actually
covered - check, per service, which of the four you can currently answer
from data versus which require you to eyeball raw logs.

**Two more instrumentation pitfalls worth knowing, both found while
building the live demo dashboard (`demo/index.html`) and confirmed by
actually exercising the running stack, not just reading code:**

- **`prometheus_client`'s in-memory registry is per-process, not
  per-application.** `worker-service` ran Celery's default "prefork"
  pool, which executes each task in a *forked child process* - but the
  metrics HTTP server ran in the parent. The `task_success`/`task_failure`
  signal handlers fired in the child, incrementing a counter the parent's
  `/metrics` endpoint could never see - `worker_tasks_total` stayed at
  zero forever, silently. Fixed by switching to `--pool=threads`, which
  keeps task execution in the same process. The exact same class of bug
  existed independently in `api-service`: `uvicorn --workers 4` ran 4
  separate processes, each with its own `tasks_db` and its own
  `api_requests_total`/`api_request_duration_seconds` - a request could
  land on any of the 4 at random, so both the task list *and* the metrics
  looked randomly inconsistent depending on which process served a given
  request. Fixed to `--workers 1` (see `docs/architecture.md` §6). The
  general lesson: any in-memory Prometheus metric (or any in-memory state
  at all) needs a story for what happens across multiple processes/pods -
  "it worked when I curled it once" does not prove it is process-safe.
- **CORS headers matter for `/metrics`, not just your main API.**
  `worker-service` exposed Prometheus metrics via
  `prometheus_client.start_http_server()`, which sends no CORS headers at
  all. `curl` doesn't care about CORS, so this passed every manual/curl
  check - it only breaks when a real browser's `fetch()` tries to read
  the response body cross-origin, which is exactly what the demo
  dashboard does. Fixed by replacing `start_http_server()` with
  `prometheus_client.make_wsgi_app()` wrapped in a small handler that adds
  `Access-Control-Allow-Origin`. Worth remembering: curl and a browser
  enforce different rules, and "it works with curl" is not the same claim
  as "it works from a browser."

---

## 5. GitOps vs. push-based CD

**This repo is push-based CD**, not GitOps, despite the README listing
ArgoCD as a technology used:
- Every deploy job (`deploy-dev`, `deploy-staging`, `deploy-production`)
  runs `kubectl apply -k ...` (or `kubectl set image`/`kubectl patch`)
  directly from the GitHub Actions runner, using a kubeconfig pulled from
  a GitHub Secret (`KUBE_CONFIG_DEV`/`_STAGING`/`_PROD`, base64-decoded
  inline in the job).
- That means: GitHub Actions holds live, direct credentials to every
  cluster, and the CI system is the thing physically pushing changes
  into the cluster. This is the traditional/"push" CD model.

**GitOps ("pull") contrast**: a GitOps controller (Argo CD, Flux) runs
*inside* the cluster (or with access scoped to it) and continuously
reconciles cluster state against a Git repo - CI's job stops at "build
the image and update a manifest/values file in a repo," and the
in-cluster controller notices the diff and applies it itself. Nothing
outside the cluster ever needs cluster-admin credentials.

| | Push (this repo) | GitOps / Pull (Argo CD, Flux) |
|---|---|---|
| Who holds cluster credentials | CI runner (GitHub Actions) | In-cluster controller only |
| Deploy trigger | CI job explicitly runs `kubectl apply` | Controller polls/watches Git and reconciles |
| Drift correction | None automatic - cluster can silently diverge from what's in Git until the next CI run | Continuous - controller re-applies Git state on any drift |
| Audit trail | GitHub Actions run logs | Git commit history *is* the audit trail (and the controller's own reconciliation logs) |
| Blast radius of a compromised CI system | High - CI can directly mutate every environment's cluster | Lower - CI never touches the cluster directly, only Git |

**Honest take**: push-based CD, as implemented here, is simpler to reason
about for a small project and is a completely legitimate starting point.
The real cost shows up at scale: credential sprawl (three separate
base64 kubeconfig secrets, one per environment, all reachable from the
same workflow file), no drift detection, and a wider blast radius if the
CI system itself is compromised. If this were being hardened toward
production, moving to Argo CD/Flux (CI only builds images and updates a
manifest repo/values file; the controller does the actual apply) is the
standard next step - and would make the README's mention of ArgoCD
actually true rather than aspirational.

---

## 6. Secrets management

**What this repo currently does**: two layers of secrets exist, and it's
worth distinguishing them:
1. **CI-time secrets** (GitHub Actions `secrets:` context) -
   `KUBE_CONFIG_DEV`/`_STAGING`/`_PROD`, `SLACK_WEBHOOK`, and the
   automatically-provided `GITHUB_TOKEN` used to authenticate to
   `ghcr.io`. These are GitHub-managed, encrypted at rest, and scoped via
   GitHub Environments - a reasonable approach for CI-time credentials
   specifically.
2. **Application-runtime secrets** - `docker-compose.yml` hardcodes
   `POSTGRES_PASSWORD=password` and a matching plaintext password in
   `DATABASE_URL` directly in the compose file for local development.
   The README's "Kubernetes" topic list mentions "ConfigMaps and
   Secrets," implying the Kubernetes manifests carry equivalent
   credentials as native Kubernetes `Secret` objects.

**Honest assessment**: a plaintext password in `docker-compose.yml` is
completely fine for local dev (it's not a real credential, never leaves
your laptop, and matches this project's own local-only Postgres
container) - don't over-index on it as a "finding." The more important
point for the exam is what a native Kubernetes `Secret` is and is not:
- A Kubernetes `Secret` is only **base64-encoded**, not encrypted, by
  default. Anyone with `get secret` RBAC access (or etcd access, if etcd
  itself isn't encrypted at rest) can read it in cleartext. It is "not
  accidentally visible in `kubectl get pod -o yaml`" more than it is
  "actually confidential."
- It has no rotation story, no audit log of who read which secret and
  when, and no dynamic/short-lived credential issuance - the same
  password lives in the Secret object until someone manually changes it
  and restarts every consumer.
- This is why "we use Kubernetes Secrets" is a fine *dev/example*
  answer but not a *production* answer on its own.

**Production-grade alternatives** (know these for the exam, and know
*why* each solves a problem plain K8s Secrets don't):
- **HashiCorp Vault**: centralized secret storage with real encryption at
  rest, fine-grained ACLs, audit logging, dynamic/short-lived credentials
  (e.g. a Vault-issued database credential that auto-expires), and secret
  leasing/rotation built in.
- **AWS Secrets Manager / GCP Secret Manager / Azure Key Vault**:
  cloud-native equivalents, integrated with the cloud's own IAM, often
  with automatic rotation for supported credential types (e.g. RDS
  passwords).
- **External Secrets Operator (ESO)**: a Kubernetes controller that
  syncs secrets *from* Vault/AWS/GCP/Azure Secret Manager *into* native
  Kubernetes `Secret` objects (or lets Pods reference them directly),
  so application manifests keep using the familiar `Secret`/env-var
  pattern while the actual secret material and rotation live in a real
  secrets manager. This is usually the pragmatic middle ground: you get
  Vault/cloud-native secret handling without every app needing native
  Vault client integration.

---

## 7. Additional exam-relevant angles this repo touches

- **Test pyramid / shift-left testing**: unit -> integration -> E2E ->
  performance ordering in the workflow (see `docs/ci-cd-pipeline.md`) is
  a textbook demonstration of the test pyramid applied to a CI pipeline's
  job ordering, not just to test-suite composition.
- **Immutable infrastructure**: images are built once (`build` job),
  tagged by SHA, and the same artifact is promoted unchanged through
  dev -> staging -> production - nothing is rebuilt or patched in place
  per environment. Compare this to the anti-pattern of "SSH into the
  server and `git pull`," which this pipeline correctly avoids.
- **Feature flags**: `apps/api-service/app.py`'s
  `/api/v1/feature-flags` endpoint (`FEATURE_NEW_UI`,
  `FEATURE_ANALYTICS`, `FEATURE_BETA` env vars) demonstrates the pattern
  of decoupling *deploy* from *release* - a flag can ship dark (deployed,
  but reading `false`) and be flipped on without a redeploy. Note this
  repo's flags are simple env-var booleans (require a redeploy or pod
  restart to change, since env vars are read at process start) rather
  than a real feature-flag service (LaunchDarkly, Unleash, etc.) that
  supports live toggling, percentage rollouts, and per-user targeting
  without any deploy at all.
- **Branch strategy**: `develop` -> dev, `main` -> staging -> production
  is a GitHub-Flow-adjacent strategy (long-lived `main`, short-lived
  feature branches, plus one additional long-lived `develop` branch acting
  as a pre-production integration branch) - closer to a simplified
  GitFlow than pure GitHub Flow. Know the difference: GitHub Flow has no
  `develop` branch at all (feature branches merge straight to `main`,
  which is always deployable); this repo's `develop` branch is a GitFlow
  holdover.
