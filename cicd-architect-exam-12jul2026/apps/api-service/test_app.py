"""
Unit tests for API Service

These run against an isolated in-memory SQLite database, not the real
Postgres from docker-compose.yml, so they stay fast and dependency-free -
matching the "unit-tests" CI job, which does not spin up a database
service (see tests/integration/ for tests against the real Postgres).
"""
import asyncio
from unittest.mock import MagicMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

import app as app_module
from app import app
from database import Base, get_db

test_engine = create_async_engine(
    "sqlite+aiosqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestSessionLocal = async_sessionmaker(test_engine, expire_on_commit=False)


async def _override_get_db():
    async with TestSessionLocal() as session:
        yield session


async def _create_tables():
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


asyncio.run(_create_tables())
app.dependency_overrides[get_db] = _override_get_db

client = TestClient(app)

def test_health_check():
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "version" in data
    assert "timestamp" in data
    assert "environment" in data

def test_root_endpoint():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "API Service Running", "docs": "/docs"}

def test_create_task():
    """Test creating a new task"""
    task_data = {
        "title": "Test Task",
        "description": "This is a test task",
        "status": "pending"
    }
    response = client.post("/api/v1/tasks", json=task_data)
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == task_data["title"]
    assert data["description"] == task_data["description"]
    assert "id" in data
    assert "created_at" in data
    return data["id"]

def test_get_tasks():
    """Test getting all tasks"""
    # Create a task first
    task_data = {
        "title": "Test Task",
        "description": "This is a test task",
        "status": "pending"
    }
    client.post("/api/v1/tasks", json=task_data)
    
    # Get all tasks
    response = client.get("/api/v1/tasks")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) > 0

def test_get_task_by_id():
    """Test getting a specific task by ID"""
    # Create a task first
    task_data = {
        "title": "Test Task",
        "description": "This is a test task",
        "status": "pending"
    }
    create_response = client.post("/api/v1/tasks", json=task_data)
    task_id = create_response.json()["id"]
    
    # Get the task by ID
    response = client.get(f"/api/v1/tasks/{task_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == task_id
    assert data["title"] == task_data["title"]

def test_get_nonexistent_task():
    """Test getting a task that doesn't exist"""
    response = client.get("/api/v1/tasks/nonexistent-id")
    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"

def test_update_task():
    """Test updating a task"""
    # Create a task first
    task_data = {
        "title": "Test Task",
        "description": "This is a test task",
        "status": "pending"
    }
    create_response = client.post("/api/v1/tasks", json=task_data)
    task_id = create_response.json()["id"]
    
    # Update the task
    updated_data = {
        "title": "Updated Task",
        "description": "This is an updated task",
        "status": "completed"
    }
    response = client.put(f"/api/v1/tasks/{task_id}", json=updated_data)
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == updated_data["title"]
    assert data["status"] == updated_data["status"]

def test_delete_task():
    """Test deleting a task"""
    # Create a task first
    task_data = {
        "title": "Test Task",
        "description": "This is a test task",
        "status": "pending"
    }
    create_response = client.post("/api/v1/tasks", json=task_data)
    task_id = create_response.json()["id"]
    
    # Delete the task
    response = client.delete(f"/api/v1/tasks/{task_id}")
    assert response.status_code == 204
    
    # Verify it's deleted
    get_response = client.get(f"/api/v1/tasks/{task_id}")
    assert get_response.status_code == 404

def test_metrics_endpoint():
    """Test Prometheus metrics endpoint"""
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "api_requests_total" in response.text

def test_trigger_demo_task(monkeypatch):
    """Test dispatching a demo background task returns the Celery task id"""
    fake_async_result = MagicMock(id="fake-task-id")
    fake_send_task = MagicMock(return_value=fake_async_result)
    monkeypatch.setattr(app_module.celery_client, "send_task", fake_send_task)

    response = client.post("/api/v1/demo/trigger-task")
    assert response.status_code == 200
    assert response.json() == {"task_id": "fake-task-id"}
    fake_send_task.assert_called_once()
    assert fake_send_task.call_args[0][0] == "worker.process_item"

def test_demo_task_status_pending(monkeypatch):
    """Test polling a task that hasn't completed yet"""
    fake_result = MagicMock(status="PENDING", result=None)
    fake_result.ready.return_value = False
    monkeypatch.setattr(app_module.celery_client, "AsyncResult", lambda task_id: fake_result)

    response = client.get("/api/v1/demo/task-status/fake-task-id")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "PENDING"
    assert data["result"] is None

def test_demo_task_status_success(monkeypatch):
    """Test polling a task that has completed successfully"""
    fake_result = MagicMock(status="SUCCESS", result={"item_id": "x", "status": "processed"})
    fake_result.ready.return_value = True
    monkeypatch.setattr(app_module.celery_client, "AsyncResult", lambda task_id: fake_result)

    response = client.get("/api/v1/demo/task-status/fake-task-id")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "SUCCESS"
    assert data["result"] == {"item_id": "x", "status": "processed"}

def test_demo_db_check_reflects_created_tasks():
    """Test the live DB-check endpoint reports a real row count from the tasks table"""
    before = client.get("/api/v1/demo/db-check").json()["row_count"]

    task_data = {"title": "DB check task", "description": "counted", "status": "pending"}
    create_response = client.post("/api/v1/tasks", json=task_data)
    task_id = create_response.json()["id"]

    after = client.get("/api/v1/demo/db-check")
    assert after.status_code == 200
    data = after.json()
    assert data["database"] == "sqlite"
    assert data["table"] == "tasks"
    assert data["row_count"] == before + 1

    client.delete(f"/api/v1/tasks/{task_id}")

def test_trace_check_reports_services_and_span_count(monkeypatch):
    """Test the trace-check endpoint reports Jaeger's known services and span count"""

    class FakeResponse:
        def __init__(self, payload):
            self._payload = payload

        def json(self):
            return self._payload

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return False

        async def get(self, url, params=None):
            if url.endswith("/api/services"):
                return FakeResponse({"data": ["api-service", "worker-service"]})
            return FakeResponse({"data": [{"spans": [1, 2, 3]}]})

    monkeypatch.setattr(app_module.httpx, "AsyncClient", FakeAsyncClient)

    response = client.get("/api/v1/demo/trace-check")
    assert response.status_code == 200
    data = response.json()
    assert data["traced_services"] == ["api-service", "worker-service"]
    assert data["most_recent_trace_span_count"] == 3

def test_feature_flags():
    """Test feature flags endpoint"""
    response = client.get("/api/v1/feature-flags")
    assert response.status_code == 200
    data = response.json()
    assert "new_ui" in data
    assert "advanced_analytics" in data
    assert "beta_features" in data