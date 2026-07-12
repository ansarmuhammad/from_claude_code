"""
Unit tests for API Service
"""
import pytest
from fastapi.testclient import TestClient
from app import app

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

def test_feature_flags():
    """Test feature flags endpoint"""
    response = client.get("/api/v1/feature-flags")
    assert response.status_code == 200
    data = response.json()
    assert "new_ui" in data
    assert "advanced_analytics" in data
    assert "beta_features" in data