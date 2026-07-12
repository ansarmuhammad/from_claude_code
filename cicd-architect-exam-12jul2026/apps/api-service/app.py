"""
API Service - FastAPI Microservice
Part of CI/CD Practice Project
"""
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime
import os
import uuid
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import PlainTextResponse
import logging
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI
app = FastAPI(
    title="API Service",
    description="Sample microservice for CI/CD practice",
    version="1.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics
request_count = Counter('api_requests_total', 'Total API requests', ['method', 'endpoint', 'status'])
request_duration = Histogram('api_request_duration_seconds', 'API request duration')

@app.middleware("http")
async def track_request_duration(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    request_duration.observe(time.time() - start_time)
    return response

# Data models
class Task(BaseModel):
    id: Optional[str] = None
    title: str
    description: str
    status: str = "pending"
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

class HealthCheck(BaseModel):
    status: str
    version: str
    timestamp: datetime
    environment: str

# In-memory storage (for demo purposes)
tasks_db = {}

# Health check endpoint
@app.get("/health", response_model=HealthCheck)
async def health_check():
    """Health check endpoint for readiness/liveness probes"""
    return HealthCheck(
        status="healthy",
        version=os.getenv("APP_VERSION", "1.0.0"),
        timestamp=datetime.now(),
        environment=os.getenv("ENVIRONMENT", "development")
    )

# Metrics endpoint
@app.get("/metrics", response_class=PlainTextResponse)
async def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

# API endpoints
@app.get("/")
async def root():
    """Root endpoint"""
    return {"message": "API Service Running", "docs": "/docs"}

@app.post("/api/v1/tasks", response_model=Task, status_code=status.HTTP_201_CREATED)
async def create_task(task: Task):
    """Create a new task"""
    task.id = str(uuid.uuid4())
    task.created_at = datetime.now()
    task.updated_at = datetime.now()
    tasks_db[task.id] = task
    
    request_count.labels(method='POST', endpoint='/api/v1/tasks', status='201').inc()
    logger.info(f"Created task: {task.id}")
    
    return task

@app.get("/api/v1/tasks", response_model=List[Task])
async def get_tasks():
    """Get all tasks"""
    request_count.labels(method='GET', endpoint='/api/v1/tasks', status='200').inc()
    return list(tasks_db.values())

@app.get("/api/v1/tasks/{task_id}", response_model=Task)
async def get_task(task_id: str):
    """Get a specific task by ID"""
    if task_id not in tasks_db:
        request_count.labels(method='GET', endpoint=f'/api/v1/tasks/{task_id}', status='404').inc()
        raise HTTPException(status_code=404, detail="Task not found")
    
    request_count.labels(method='GET', endpoint=f'/api/v1/tasks/{task_id}', status='200').inc()
    return tasks_db[task_id]

@app.put("/api/v1/tasks/{task_id}", response_model=Task)
async def update_task(task_id: str, task: Task):
    """Update a task"""
    if task_id not in tasks_db:
        request_count.labels(method='PUT', endpoint=f'/api/v1/tasks/{task_id}', status='404').inc()
        raise HTTPException(status_code=404, detail="Task not found")
    
    task.id = task_id
    task.updated_at = datetime.now()
    tasks_db[task_id] = task
    
    request_count.labels(method='PUT', endpoint=f'/api/v1/tasks/{task_id}', status='200').inc()
    logger.info(f"Updated task: {task_id}")
    
    return task

@app.delete("/api/v1/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(task_id: str):
    """Delete a task"""
    if task_id not in tasks_db:
        request_count.labels(method='DELETE', endpoint=f'/api/v1/tasks/{task_id}', status='404').inc()
        raise HTTPException(status_code=404, detail="Task not found")
    
    del tasks_db[task_id]
    request_count.labels(method='DELETE', endpoint=f'/api/v1/tasks/{task_id}', status='204').inc()
    logger.info(f"Deleted task: {task_id}")
    
    return None

# Feature flag endpoint (for demonstrating progressive delivery)
@app.get("/api/v1/feature-flags")
async def get_feature_flags():
    """Get feature flags for the application"""
    return {
        "new_ui": os.getenv("FEATURE_NEW_UI", "false").lower() == "true",
        "advanced_analytics": os.getenv("FEATURE_ANALYTICS", "false").lower() == "true",
        "beta_features": os.getenv("FEATURE_BETA", "false").lower() == "true"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)