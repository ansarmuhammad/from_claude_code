"""
Integration tests for api-service.

These tests exercise the real api-service container over HTTP, as brought
up by `docker-compose -f docker/docker-compose.test.yml up -d` in the CI
pipeline (.github/workflows/ci-cd-pipeline.yml). They assume the service is
already running and reachable - they do not start or stop containers
themselves.

Run locally:
    docker-compose -f docker/docker-compose.test.yml up -d
    pytest tests/integration/ -v
    docker-compose -f docker/docker-compose.test.yml down
"""
import os
import uuid

import httpx
import pytest

BASE_URL = os.getenv("API_BASE_URL", "http://localhost:8000")
TIMEOUT = float(os.getenv("API_TEST_TIMEOUT", "10"))


@pytest.fixture(scope="session")
def client():
    with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT) as c:
        yield c


@pytest.fixture()
def created_task(client):
    """Create a task and clean it up afterwards, regardless of test outcome."""
    payload = {
        "title": f"integration-test-{uuid.uuid4().hex[:8]}",
        "description": "created by integration test suite",
        "status": "pending",
    }
    response = client.post("/api/v1/tasks", json=payload)
    assert response.status_code == 201
    task = response.json()
    yield task
    client.delete(f"/api/v1/tasks/{task['id']}")


def test_health_check_reports_healthy(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data
    assert "timestamp" in data
    assert "environment" in data


def test_root_endpoint_returns_service_banner(client):
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["message"] == "API Service Running"
    assert data["docs"] == "/docs"


def test_metrics_endpoint_exposes_prometheus_series(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "api_requests_total" in response.text
    assert "api_request_duration_seconds" in response.text


def test_create_task_returns_created_resource(client):
    payload = {
        "title": "Write integration tests",
        "description": "Cover the api-service CRUD flow end to end",
        "status": "pending",
    }
    response = client.post("/api/v1/tasks", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == payload["title"]
    assert data["description"] == payload["description"]
    assert data["status"] == "pending"
    assert data["id"]
    assert data["created_at"]
    assert data["updated_at"]
    client.delete(f"/api/v1/tasks/{data['id']}")


def test_get_tasks_includes_newly_created_task(client, created_task):
    response = client.get("/api/v1/tasks")
    assert response.status_code == 200
    tasks = response.json()
    assert isinstance(tasks, list)
    assert any(t["id"] == created_task["id"] for t in tasks)


def test_get_task_by_id_returns_matching_task(client, created_task):
    response = client.get(f"/api/v1/tasks/{created_task['id']}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == created_task["id"]
    assert data["title"] == created_task["title"]


def test_get_nonexistent_task_returns_404(client):
    response = client.get("/api/v1/tasks/does-not-exist")
    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"


def test_update_task_persists_changes(client, created_task):
    updated_payload = {
        "title": "Updated via integration test",
        "description": "Updated description",
        "status": "completed",
    }
    response = client.put(f"/api/v1/tasks/{created_task['id']}", json=updated_payload)
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == created_task["id"]
    assert data["title"] == updated_payload["title"]
    assert data["status"] == "completed"

    follow_up = client.get(f"/api/v1/tasks/{created_task['id']}")
    assert follow_up.json()["status"] == "completed"


def test_delete_task_removes_it(client):
    payload = {
        "title": "Temporary task",
        "description": "Will be deleted",
        "status": "pending",
    }
    create_response = client.post("/api/v1/tasks", json=payload)
    task_id = create_response.json()["id"]

    delete_response = client.delete(f"/api/v1/tasks/{task_id}")
    assert delete_response.status_code == 204

    get_response = client.get(f"/api/v1/tasks/{task_id}")
    assert get_response.status_code == 404


def test_feature_flags_endpoint_returns_expected_keys(client):
    response = client.get("/api/v1/feature-flags")
    assert response.status_code == 200
    data = response.json()
    assert set(data.keys()) == {"new_ui", "advanced_analytics", "beta_features"}
    assert all(isinstance(v, bool) for v in data.values())
