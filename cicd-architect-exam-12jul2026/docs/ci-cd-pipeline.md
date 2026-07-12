# CI/CD Pipeline Walkthrough

This walks through `.github/workflows/ci-cd-pipeline.yml` stage by stage:
what each job does, why it's ordered where it is, and which general CI/CD
architecture principle it is meant to demonstrate. Job names below match
the `name:` fields in the workflow file exactly.

Trigger: `push` to `main`/`develop`, `pull_request` targeting `main`, and
`workflow_dispatch` (manual trigger). Two branches drive two different
depths of pipeline: `develop` reaches dev, `main` reaches dev -> staging ->
production.

## 1. `code-quality` (Code Quality Check)

Runs Black (format check), Flake8 (lint), MyPy (types), Bandit (SAST for
Python), and Safety (dependency vulnerability check) against `apps/`.

- **Purpose**: catch cheap, deterministic problems (formatting, obvious
  bugs, known-vulnerable dependencies) before spending CI minutes on
  slower jobs like builds and integration tests.
- **Principle demonstrated: fail-fast ordering.** This is the first job
  and has no dependencies (`needs:` is absent), so it starts immediately
  and, if it fails, nothing downstream even attempts to run. Putting the
  cheapest, fastest checks first is a core CI/CD architecture principle -
  it minimizes the time-to-feedback for the most common class of
  failures (style/lint issues) and avoids wasting compute on a build that
  a linter would have already told you is broken.
- **Trade-off**: Bandit and Safety here run in "warn but don't gate"
  mode by default unless you configure them to fail-the-build - as
  written, `bandit ... -f json -o bandit-report.json` and
  `safety check --json` produce reports but the workflow doesn't
  necessarily fail the job on findings (that depends on each tool's exit
  code semantics and whether `-json`/reporting flags suppress a non-zero
  exit). Worth checking in a real pipeline: an "SAST job" that never
  fails the build isn't a gate, it's a report nobody reads.

## 2. `unit-tests` (Unit Tests)

Matrix over `service: [api-service, worker-service]`, each running
`pytest test_*.py --cov=. --cov-report=xml --cov-report=term --junitxml=junit.xml`.

- **Purpose**: verify each service's own logic in isolation, fast, with
  coverage reporting uploaded to Codecov per-service via `flags:`.
- **Principle demonstrated: matrix builds.** Rather than writing two
  near-identical jobs, the `strategy: matrix:` block runs the same steps
  once per service in parallel runners. This is the standard pattern for
  "same steps, different inputs" and keeps the workflow file DRY while
  still giving independent pass/fail signal per service (a failure in
  worker-service's tests doesn't hide a failure in api-service's, and
  vice versa - both show up as separate check runs).
- **Principle demonstrated: caching.** `actions/cache@v3` keyed on
  `hashFiles('**/requirements.txt')` avoids re-downloading pip packages
  on every run; the cache key changing only when `requirements.txt`
  changes is the standard "invalidate only when the input changes"
  caching pattern.
- Runs in parallel with nothing but `code-quality` as a prerequisite? -
  actually `unit-tests` has no `needs:` either, so both `code-quality`
  and `unit-tests` start concurrently. Only `build` waits on both. This
  is a reasonable choice: lint and unit-test failures are independent
  causes, so there's no reason to serialize them - only the expensive
  `build` step needs to wait for both to be green.

## 3. `build` (Build Docker Images)

`needs: [code-quality, unit-tests]`. Matrix over all three services this
time (`api-service, web-frontend, worker-service`). Uses Buildx,
`docker/metadata-action` for tag generation, and
`docker/build-push-action` with `cache-from/cache-to: type=gha` and
multi-platform (`linux/amd64,linux/arm64`) output, pushed to
`ghcr.io/${{ github.repository }}/<service>`.

- **Purpose**: produce the immutable, versioned artifacts (container
  images) that every later stage deploys, unmodified. Nothing downstream
  ever rebuilds - it only ever pulls-and-deploys what this job pushed.
- **Principle demonstrated: fail-fast ordering, again.** Building three
  images (especially multi-arch) is expensive; gating it behind both
  quality gates means a formatting typo or a broken unit test never
  triggers a wasted multi-arch build.
- **Principle demonstrated: build caching.** GitHub Actions cache
  (`type=gha`) is layer-aware, so unchanged Docker layers (e.g. the
  dependency-install layer, per the multi-stage Dockerfiles in `docker/`)
  are reused across runs instead of rebuilt from scratch - this is the
  same "cache the expensive, rarely-changing part" idea as step 2's pip
  cache, applied at the container layer.
- **Principle demonstrated: immutable, content-addressed artifacts.**
  `docker/metadata-action` tags each image several ways at once (branch
  ref, PR ref, semver, and `sha`-prefixed) so that a given commit maps to
  a traceable, reproducible image - this is what lets `deploy-production`
  later reference `${{ github.sha }}` specifically rather than a
  floating `:latest`, avoiding "what's actually running in prod?"
  ambiguity.

## 4. `container-scan` (Container Security Scan)

`needs: build`. Matrix over all three services again; runs Trivy against
each just-built image (`image-ref: .../<service>:${{ github.sha }}`),
severity filtered to `CRITICAL,HIGH`, uploading SARIF results to GitHub
Security via `codeql-action/upload-sarif`.

- **Purpose**: catch known-CVE vulnerable OS packages/libraries baked
  into the final image - a different concern from `code-quality`'s Bandit
  step, which only looks at first-party Python source, not what actually
  ships inside the container (base image packages, transitive OS libs,
  etc.).
- **Principle demonstrated: security scanning as a gate, not an
  afterthought.** Placing this immediately after `build` (rather than,
  say, only before `deploy-production`) means a vulnerable image is
  flagged before it's ever deployed anywhere, including dev. This is the
  DevSecOps "shift left" principle: security feedback as early as
  practical, on every build, not just periodically or pre-release.
- **Caveat worth noting for the exam**: as written, this job *uploads*
  findings to GitHub Security but does not appear to explicitly `exit 1`
  the job on CRITICAL/HIGH findings (Trivy's default action behavior
  depends on configured `exit-code`/`limit-severity` inputs). A truly
  "gating" scan needs to fail the pipeline on disallowed severities, not
  just record them for later review - otherwise it's an audit trail, not
  a gate. See `docs/exam-prep-notes.md` for more on this distinction.
- Runs in parallel with `integration-tests` (both only `need: build`).

## 5. `integration-tests` (Integration Tests)

`needs: build`. Spins up ephemeral `postgres` and `redis` **service
containers** (GitHub Actions' `services:` block, with health checks),
then separately does `docker-compose -f docker/docker-compose.test.yml up
-d`, sleeps 10s, and runs `pytest tests/integration/ -v`.

- **Purpose**: verify that api-service and worker-service actually work
  *together* through real Postgres/Redis, not mocks - the class of bug
  that unit tests structurally cannot catch (wrong SQL, wrong Celery
  routing, serialization mismatches across the process boundary).
- **Principle demonstrated: test pyramid progression.** Unit tests (fast,
  isolated, step 2) run before integration tests (slower, real
  dependencies, this step), which in turn run before E2E tests (slowest,
  full stack, step 7). Each layer only runs once the cheaper layer below
  it has passed, which is the CI/CD expression of the classic test
  pyramid: many fast unit tests, fewer integration tests, fewer still E2E.
- **Trade-off worth flagging**: this job both leans on GitHub Actions
  `services:` (for postgres/redis) *and* separately spins up
  `docker/docker-compose.test.yml`. Depending on what's in that compose
  file, this could mean duplicate Postgres/Redis instances are running
  simultaneously - worth checking for redundancy in a real pipeline. A
  fixed `sleep 10` (rather than polling a health/readiness endpoint) is
  also a classic CI flakiness source: it works until the container is
  ever slower to start than 10 seconds, at which point tests fail
  intermittently for reasons unrelated to the code under test.

## 6. `deploy-dev` (Deploy to Development)

`needs: [integration-tests, container-scan]`, gated further by
`if: github.ref == 'refs/heads/develop'`. Configures kubectl from a
base64-encoded `KUBE_CONFIG_DEV` secret, runs
`kubectl apply -k kubernetes/overlays/dev/`, checks rollout status for all
three deployments in the `development` namespace, then curls `/health`
through the Service's LoadBalancer IP as a smoke test.

- **Purpose**: get every merge to `develop` running somewhere real,
  fast, with minimal ceremony - a low-stakes environment to catch
  "works on my machine" class issues.
- **Principle demonstrated: progressive delivery, stage 1 of 3.**
  Dev is the first of three ascending-risk environments (dev -> staging
  -> production); each requires everything before it to pass, and each
  environment is closer in shape to production than the last.
- **Principle demonstrated: GitHub Environments as deployment gates.**
  The `environment: name: development` block ties this job to a GitHub
  Environment, which is where you'd configure required reviewers, wait
  timers, or environment-scoped secrets (`KUBE_CONFIG_DEV` is scoped this
  way) - a structural mechanism for separating "who can approve a
  production deploy" from "who can approve a dev deploy," even though
  this workflow doesn't currently add manual approval gates on any of the
  three environments.
- **Push-based CD**: note that GitHub Actions itself holds the
  kubeconfig and directly runs `kubectl apply`. This is "push" CD, as
  opposed to GitOps/"pull" CD (e.g. Argo CD watching a repo and
  reconciling on its own). See `docs/exam-prep-notes.md` for the
  contrast - the README lists ArgoCD as a technology used, but this
  workflow does not actually use it; it's a push-based pipeline
  throughout.

## 7. `deploy-staging` (Deploy to Staging)

`needs: deploy-dev`, gated by `if: github.ref == 'refs/heads/main'`.
Applies `kubernetes/overlays/staging/`, then does an explicit
`kubectl set image deployment/api-service ...:${{ github.sha }}` before
checking rollout status, then installs Playwright and runs
`playwright test tests/e2e/`.

- **Purpose**: staging is where the pipeline both deploys the exact
  commit SHA's image (not just whatever the overlay's base manifest
  points to) and runs full browser-driven E2E tests against a live,
  deployed environment - the closest pre-production approximation of
  real user traffic.
- **Note on naming vs. mechanism**: the job's inline comment says
  "Deploy to Kubernetes with Canary," but the actual command
  (`kubectl set image` on the existing Deployment, followed by a single
  `rollout status` wait) is a standard **rolling update**, not a canary
  deployment - a real canary would route a small percentage of traffic to
  the new version, watch metrics, and only then shift 100% (typically
  via a service mesh, an Ingress weighting rule, or Argo Rollouts /
  Flagger). This mismatch between the comment and the mechanism is worth
  noticing: **the label "canary" in a workflow doesn't make a rolling
  update into one.** See `docs/exam-prep-notes.md` for how canary,
  blue/green, and rolling updates actually differ.
- **Principle demonstrated: progressive delivery + observability feedback
  loop.** E2E tests here act as an automated go/no-go gate before
  production is even attempted - the pipeline only reaches
  `deploy-production` if Playwright's assertions against the *real*
  deployed staging system pass.

## 8. `deploy-production` (Deploy to Production) - Blue/Green

`needs: deploy-staging`, gated by `if: github.ref == 'refs/heads/main'`.
The actual mechanism:
```yaml
kubectl apply -k kubernetes/overlays/production/green/
kubectl wait --for=condition=ready pod -l app=api-service,version=green -n production --timeout=300s
kubectl patch service api-service -n production -p '{"spec":{"selector":{"version":"green"}}}'
sleep 30
kubectl apply -k kubernetes/overlays/production/blue/
```
followed by a Slack notification (`if: always()`, so it fires on both
success and failure).

- **Purpose**: this *is* a genuine blue/green deployment - two full,
  independent sets of pods (`version=blue` and `version=green`) exist
  simultaneously, and a single Service selector patch is what atomically
  switches which one receives live traffic.
- **Principle demonstrated: progressive delivery, final stage, with
  instant rollback capability.** Because both versions keep running
  after the switch (blue isn't torn down, just re-applied/refreshed for
  next time), rolling back a bad production release is, in principle, as
  fast as patching the selector back to `blue` - much faster than
  waiting for a rolling update to reverse itself pod-by-pod. This is
  blue/green's core advantage over a rolling update: near-instant
  cutover and near-instant rollback, at the cost of running 2x the pod
  capacity for the duration of the switch.
- **Gap worth flagging (be honest about it)**: the `sleep 30` after the
  traffic switch is not a verification step - it's a fixed pause with
  nothing actually checking error rates, latency, or health during those
  30 seconds before `blue` gets re-applied. A production-grade blue/green
  process would gate the "refresh blue" step (and, more importantly, gate
  *staying* on green at all) on real signals - error rate/latency from
  Prometheus, or a synthetic smoke test - not a fixed sleep. As written,
  if green is broken, the workflow has already reported success (Slack
  notification fires on `job.status`, which reflects whether the
  `kubectl` commands executed without error, not whether the new version
  is actually healthy) by the time anyone would notice from the pipeline
  alone. Detecting a bad green deploy currently depends on a human
  watching Grafana/alerts and manually re-patching the selector - see
  `docs/runbook.md`.
- **Principle demonstrated: observability feedback loop, partially.**
  The Slack notification is a real feedback loop (someone gets pinged),
  but it reports pipeline execution status, not deployment health -
  worth distinguishing "the steps ran" from "the release is good" when
  designing your own gates.

## 9. `performance-test` (Performance Testing)

`needs: deploy-staging` (note: **not** `deploy-production` - it runs
against staging, in parallel with `deploy-production`), gated by
`if: github.ref == 'refs/heads/main'`. Runs k6
(`tests/performance/load-test.js`) via `grafana/k6-action`, uploading
JSON results as an artifact.

- **Purpose**: catch performance regressions (latency, throughput,
  error rate under load) using the staging deployment, without adding
  load-testing latency to the production release path.
- **Principle demonstrated: non-blocking quality signal, decoupled from
  the release gate.** Because this job depends only on `deploy-staging`
  and not on `deploy-production`, it runs concurrently with the
  production deployment rather than gating it. That's a deliberate
  trade-off: production ships as soon as staging + E2E are green, and
  performance results become available slightly later for review -
  faster time-to-production, at the cost of the performance suite not
  being able to block a bad release before it reaches users. Whether
  that trade-off is correct depends on how expensive a production
  performance regression is versus how much release velocity you need;
  it's a defensible choice for a scaffold, but worth naming explicitly
  as a choice rather than an oversight.

## Summary: what "good CI/CD architecture" this pipeline demonstrates well, and where it falls short

**Demonstrated well:**
- Fail-fast ordering (quality/unit tests before build; build before scan/integration; integration+scan before deploy)
- Matrix builds for both tests and image builds
- Dependency and layer caching (pip cache, `type=gha` Docker layer cache)
- Immutable, SHA-addressable artifacts promoted unchanged across environments
- A real, working blue/green mechanism for production (not just a label)
- Security scanning positioned early (shift-left) rather than only pre-release
- A three-stage progressive delivery model (dev -> staging -> production) with E2E as a staging gate

**Falls short of production-grade (see `docs/exam-prep-notes.md` for the full discussion):**
- No manual approval gate before production (main -> production is fully automatic once staging/E2E pass)
- Container scan may not actually fail the build on findings (report vs. gate)
- Blue/green's post-switch verification is a fixed `sleep 30`, not a real health/metrics check
- The "canary" comment in `deploy-staging` doesn't match the rolling-update mechanism actually used
- Slack notification reports pipeline execution success, not release health
