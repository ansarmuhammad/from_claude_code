# On-Call Runbook

Incident response procedures for the three services (api-service,
web-frontend, worker-service) and their data stores (PostgreSQL, Redis).
Each scenario follows: **Detection -> Diagnosis -> Remediation**.

Namespace reference (matches `scripts/deploy.sh` / the GitHub Actions
workflow):

| Environment | Namespace     |
|-------------|---------------|
| dev         | `development` |
| staging     | `staging`     |
| production  | `production`  |

Set `NS` to the relevant namespace before running the example commands
below, e.g. `NS=production`.

---

## Scenario 1: Service is down (pods not Ready / 5xx from everything)

### Detection
- Grafana: the service's request-rate/uptime panel drops to zero, or the
  `/health` synthetic check (if configured) starts failing.
- Prometheus alert on `up{job="<service>"} == 0` (target unscrapeable) or
  on a sustained drop in `api_requests_total` rate to zero.
- Manual: `curl -f https://<env-url>/health` returns non-200 or times out
  (the same check `deploy-dev`'s smoke test performs).

### Diagnosis
```bash
# Pod status - look for CrashLoopBackOff, ImagePullBackOff, Pending
kubectl get pods -n "$NS" -l app=api-service -o wide

# Recent events (OOMKilled, failed scheduling, failed probes, etc.)
kubectl describe pod -n "$NS" -l app=api-service | tail -50
kubectl get events -n "$NS" --sort-by='.lastTimestamp' | tail -30

# Application logs from the current and (if crash-looping) previous container
kubectl logs -n "$NS" -l app=api-service --tail=200
kubectl logs -n "$NS" -l app=api-service --previous --tail=200

# Is the Deployment even trying to run the right image?
kubectl get deployment api-service -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# Is the Service routing to any Ready endpoints at all?
kubectl get endpoints api-service -n "$NS"
```

### Remediation
- **Bad image / crash-looping since the last deploy**: this is the most
  common cause. Roll back immediately rather than debugging live in
  production:
  ```bash
  ./scripts/rollback.sh <dev|staging|production>
  ```
  For production specifically, if traffic was already switched to
  `version=green` via blue/green and `green` is the broken side, the
  *fastest* fix is re-pointing the Service selector back to blue rather
  than waiting on `rollout undo`:
  ```bash
  kubectl patch service api-service -n production -p '{"spec":{"selector":{"version":"blue"}}}'
  ```
  Then use `scripts/rollback.sh production` to bring the Deployment
  objects themselves back in line once the immediate incident is
  contained.
- **Dependency down (Postgres/Redis unreachable)**: see Scenario 3 -
  fix the dependency, the service should recover on its own once it can
  connect (check `restartPolicy`/readiness probe behavior - if the app
  doesn't retry connections gracefully, a pod restart may be required
  after the dependency is healthy again: `kubectl rollout restart
  deployment/api-service -n "$NS"`).
- **Resource exhaustion (OOMKilled / evicted)**: check
  `kubectl describe pod` for `OOMKilled` in the last state, then either
  raise the Deployment's memory limit (short-term) or investigate a
  memory leak (longer-term) - do not just keep restarting.

---

## Scenario 2: High error rate (5xx / task failures elevated, but service is up)

### Detection
- Grafana/Prometheus alert on the error-rate golden signal, e.g.
  `sum(rate(api_requests_total{status=~"5.."}[5m])) / sum(rate(api_requests_total[5m])) > 0.05`
  (5% error budget burn - tune the threshold to your actual SLO).
- Worker-side equivalent:
  `sum(rate(worker_tasks_total{status="failure"}[5m])) by (task_name)`
  spiking for a specific task.
- Pods report `Ready` (so Scenario 1 doesn't apply) but users/synthetic
  checks report failures.

### Diagnosis
```bash
# Confirm it's real and see which endpoints/status codes are affected
# (query via Prometheus/Grafana Explore, example PromQL):
#   sum by (endpoint, status) (rate(api_requests_total[5m]))

# Correlate with a recent deploy
kubectl rollout history deployment/api-service -n "$NS"

# Tail logs for the actual error payloads/stack traces
kubectl logs -n "$NS" -l app=api-service --tail=200 -f

# For worker-side failures, check which task type is failing and why
kubectl logs -n "$NS" -l app=worker-service --tail=200 -f
```

### Remediation
- **Correlates with a recent deploy** (rollout history timestamp lines up
  with the error-rate spike): this is a deployment rollback situation -
  jump to Scenario 4.
- **Does not correlate with a deploy** (errors started without a release,
  e.g. a downstream dependency degraded, a data-driven edge case, or a
  traffic spike): investigate the specific error payloads in logs first;
  do not reflexively roll back if nothing was actually deployed - you'd
  be "rolling back" to the same code that's already running.
- **Traffic-induced** (error rate rises with request volume, e.g.
  connection pool exhaustion under load): see Scenario 3 for the
  database-connection-specific version of this; more generally, consider
  scaling out (`kubectl scale deployment/api-service --replicas=N -n
  "$NS"`) as an immediate mitigation while investigating root cause.

---

## Scenario 3: Database connection exhaustion

### Detection
- Application logs show connection errors (`too many connections`,
  `connection pool exhausted`, timeouts acquiring a DB connection).
- Postgres-side: `pg_stat_activity` count approaching `max_connections`.
- Elevated latency/error rate on any endpoint that touches the DB,
  often correlated with worker-service task failures too (both
  api-service and worker-service share the same Postgres instance in
  this architecture - see `docs/architecture.md` section 3).

### Diagnosis
```bash
# From the postgres pod/container, check current vs max connections
kubectl exec -it -n "$NS" deploy/postgres -- \
  psql -U user -d appdb -c "SELECT count(*) FROM pg_stat_activity;"
kubectl exec -it -n "$NS" deploy/postgres -- \
  psql -U user -d appdb -c "SHOW max_connections;"

# See what's actually holding connections open - look for many
# long-running or idle-in-transaction sessions
kubectl exec -it -n "$NS" deploy/postgres -- \
  psql -U user -d appdb -c "SELECT pid, state, query, now() - query_start AS duration FROM pg_stat_activity ORDER BY duration DESC LIMIT 20;"

# Cross-check how many api-service / worker-service replicas are running -
# connection exhaustion is often just (replica count) x (per-pod pool size) > max_connections
kubectl get deployment api-service worker-service -n "$NS"
```

### Remediation
- **Immediate relief**: terminate long-running/idle-in-transaction
  sessions identified above (only after confirming they're not doing
  legitimate long work):
  ```sql
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = <pid>;
  ```
- **Structural fix, short-term**: reduce per-pod connection pool size or
  reduce replica count temporarily so `replicas x pool_size <
  max_connections` again.
- **Structural fix, longer-term**: put a connection pooler (PgBouncer)
  in front of Postgres so application pods pool against PgBouncer rather
  than each holding direct Postgres connections - this decouples "how
  many app replicas can I run" from "how many Postgres connections
  exist," which is the real fix rather than a recurring firefight.
- **If a recent scale-up or deploy caused this** (more replicas than the
  DB was sized for): `./scripts/rollback.sh <env>` or
  `kubectl scale deployment/api-service --replicas=<previous-N> -n "$NS"`
  as an immediate mitigation while the pooling/sizing fix is planned.

---

## Scenario 4: Deployment rollback needed

### Detection
- Any of Scenario 1/2's alerts firing shortly after a known deploy
  (check `kubectl rollout history`, or correlate with the CI/CD
  pipeline's deploy job timestamps in GitHub Actions).
- A human (on-call, or whoever is watching the blue/green cutover per
  `docs/ci-cd-pipeline.md` section 8) decides the new version should not
  keep serving traffic.

### Diagnosis
```bash
# Confirm current vs previous image/revision
kubectl rollout history deployment/api-service -n "$NS"
kubectl rollout history deployment/api-service -n "$NS" --revision=<N>   # inspect a specific past revision

# Confirm this is actually a code/config regression and not a dependency
# outage that rolling back won't fix (see Scenario 1/3 first)
```

### Remediation
Use `scripts/rollback.sh` rather than raw `kubectl` commands where
possible - it runs the rollback for all three services consistently and
enforces a confirmation prompt for production:
```bash
# Roll back to the previous revision
./scripts/rollback.sh dev
./scripts/rollback.sh staging
./scripts/rollback.sh production          # prompts for confirmation

# Roll back to a specific revision
./scripts/rollback.sh staging 4

# Non-interactive (e.g. from an automated incident-response tool)
CONFIRM=yes ./scripts/rollback.sh production
```

For **production specifically**, remember the blue/green nuance from
Scenario 1: if the bad release is the `green` side and `blue` is still
intact and idle, patching the Service selector back to `blue` is faster
than waiting on `rollout undo` to reverse a rolling update. Do that
first to stop user impact, then run `scripts/rollback.sh production` to
bring the Deployment objects themselves back in sync, and finally
confirm via:
```bash
kubectl rollout status deployment/api-service -n production
kubectl rollout status deployment/web-frontend -n production
kubectl rollout status deployment/worker-service -n production
```

### Post-incident
- Confirm error rate / latency dashboards return to baseline after the
  rollback (don't declare victory on "the command exited 0" - see the
  critique in `docs/ci-cd-pipeline.md` section 8 about the difference
  between "the deploy step ran" and "the release is actually healthy").
- File a follow-up to fix the container-scan/blue-green verification
  gaps noted in `docs/exam-prep-notes.md` if this incident was the kind
  a real health-gated rollout would have caught automatically before it
  ever reached users.
