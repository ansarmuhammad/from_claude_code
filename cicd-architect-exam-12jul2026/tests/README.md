# Tests

This project's test pyramid, and how to run each layer locally. Layers
mirror the jobs in `.github/workflows/ci-cd-pipeline.yml`.

## 1. Unit tests

Live next to the source they test: `apps/api-service/test_app.py` and
`apps/worker-service/test_worker.py`.

```bash
cd apps/api-service
pip install -r requirements.txt pytest pytest-cov pytest-asyncio
pytest test_*.py --cov=. --cov-report=term

cd ../worker-service
pip install -r requirements.txt pytest pytest-cov pytest-asyncio
pytest test_*.py --cov=. --cov-report=term
```

## 2. Integration tests (`tests/integration/`)

Run against the real api-service (+ postgres/redis/worker-service)
containers defined in `docker/docker-compose.test.yml`. `test_api_integration.py`
talks to the api-service over HTTP using `httpx`, exercising the health
check and the full task CRUD flow (`/api/v1/tasks`).

```bash
docker-compose -f docker/docker-compose.test.yml up -d

pip install pytest pytest-asyncio httpx
pytest tests/integration/ -v

docker-compose -f docker/docker-compose.test.yml down
```

The base URL defaults to `http://localhost:8000`. Override it with:

```bash
API_BASE_URL=http://localhost:8000 pytest tests/integration/ -v
```

## 3. End-to-end tests (`tests/e2e/`)

Playwright tests that drive `web-frontend` (http://localhost:3000) through
the browser: load the page, confirm the health indicator, create a task via
the UI form, and confirm it shows up in the task list. Configuration lives in
`playwright.config.ts` at the repo root.

```bash
npm install -D @playwright/test
npx playwright install --with-deps chromium

docker-compose up -d api-service web-frontend postgres redis

npx playwright test tests/e2e/
```

Override the target with `WEB_FRONTEND_URL=http://localhost:3000`.

## 4. Performance tests (`tests/performance/`)

A k6 script that ramps virtual users up against `GET /health` and
`GET /api/v1/tasks` on api-service, asserting p95 latency < 500ms and an
error rate < 1%.

```bash
brew install k6   # or see https://k6.io/docs/get-started/installation/

docker-compose up -d api-service postgres redis

k6 run tests/performance/load-test.js
```

Override the target with `API_BASE_URL=http://localhost:8000 k6 run tests/performance/load-test.js`.

## Where each suite runs in CI

| Suite       | Workflow job          | Command                                          |
|-------------|------------------------|---------------------------------------------------|
| Unit        | `unit-tests`           | `pytest test_*.py --cov=. ...` (per service)      |
| Integration | `integration-tests`    | `docker-compose -f docker/docker-compose.test.yml up -d` then `pytest tests/integration/ -v` |
| E2E         | `deploy-staging`        | `playwright test tests/e2e/`                      |
| Performance | `performance-test`     | `grafana/k6-action` running `tests/performance/load-test.js` |
