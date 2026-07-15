"""
API Service - FastAPI Microservice
Part of CI/CD Practice Project
"""
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
from datetime import datetime
import os
import uuid
import httpx
from celery import Celery
from opentelemetry.instrumentation.celery import CeleryInstrumentor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import PlainTextResponse
import logging
import time

from database import Base, engine, get_db
from models import TaskRecord
from tracing import setup_tracing

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

setup_tracing("api-service")
CeleryInstrumentor().instrument()
SQLAlchemyInstrumentor().instrument(engine=engine.sync_engine)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Postgres may not accept connections the instant this process starts
    # even with a compose healthcheck-based depends_on, so retry briefly
    # instead of crashing on the first attempt.
    for attempt in range(1, 6):
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            break
        except Exception as exc:
            logger.warning(f"Database not ready (attempt {attempt}/5): {exc}")
            await asyncio.sleep(2)
    yield


# Initialize FastAPI
app = FastAPI(
    title="API Service",
    description="Sample microservice for CI/CD practice",
    version="1.0.0",
    lifespan=lifespan,
)
FastAPIInstrumentor.instrument_app(app)

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
async def track_request_metrics(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    request_duration.observe(time.time() - start_time)
    # Label by the route's path template (e.g. "/api/v1/tasks/{task_id}"), not
    # request.url.path - using the resolved path would create a new
    # Prometheus time series per unique task id, growing without bound.
    route = request.scope.get("route")
    endpoint = route.path if route else request.url.path
    request_count.labels(method=request.method, endpoint=endpoint, status=str(response.status_code)).inc()
    return response

# Data models
class Task(BaseModel):
    model_config = ConfigDict(from_attributes=True)

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

# Celery client used only to dispatch/poll demo background jobs on worker-service
celery_client = Celery(
    "api_service_client",
    broker=os.getenv("CELERY_BROKER_URL", "redis://localhost:6379/0"),
    backend=os.getenv("CELERY_RESULT_BACKEND", "redis://localhost:6379/1"),
)

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
async def create_task(task: Task, db: AsyncSession = Depends(get_db)):
    """Create a new task"""
    task.id = str(uuid.uuid4())
    task.created_at = datetime.now()
    task.updated_at = datetime.now()

    record = TaskRecord(
        id=task.id,
        title=task.title,
        description=task.description,
        status=task.status,
        created_at=task.created_at,
        updated_at=task.updated_at,
    )
    db.add(record)
    await db.commit()

    logger.info(f"Created task: {task.id}")

    return task

@app.get("/api/v1/tasks", response_model=List[Task])
async def get_tasks(db: AsyncSession = Depends(get_db)):
    """Get all tasks"""
    result = await db.execute(select(TaskRecord))
    return result.scalars().all()

@app.get("/api/v1/tasks/{task_id}", response_model=Task)
async def get_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """Get a specific task by ID"""
    record = await db.get(TaskRecord, task_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Task not found")

    return record

@app.put("/api/v1/tasks/{task_id}", response_model=Task)
async def update_task(task_id: str, task: Task, db: AsyncSession = Depends(get_db)):
    """Update a task"""
    record = await db.get(TaskRecord, task_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Task not found")

    record.title = task.title
    record.description = task.description
    record.status = task.status
    record.updated_at = datetime.now()
    await db.commit()
    await db.refresh(record)

    logger.info(f"Updated task: {task_id}")

    return record

@app.delete("/api/v1/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    """Delete a task"""
    record = await db.get(TaskRecord, task_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Task not found")

    await db.delete(record)
    await db.commit()
    logger.info(f"Deleted task: {task_id}")

    return None

@app.post("/api/v1/demo/trigger-task")
async def trigger_demo_task():
    """Dispatch a real Celery task to worker-service, for the live demo dashboard"""
    async_result = celery_client.send_task(
        "worker.process_item", args=[str(uuid.uuid4()), {"source": "demo-dashboard"}]
    )
    return {"task_id": async_result.id}

@app.get("/api/v1/demo/task-status/{task_id}")
async def demo_task_status(task_id: str):
    """Poll the status/result of a task dispatched via /api/v1/demo/trigger-task"""
    async_result = celery_client.AsyncResult(task_id)
    return {
        "task_id": task_id,
        "status": async_result.status,
        "result": async_result.result if async_result.ready() else None,
    }

@app.get("/api/v1/demo/db-check")
async def demo_db_check(db: AsyncSession = Depends(get_db)):
    """Prove tasks are really persisted in the database, for the live demo dashboard"""
    result = await db.execute(select(func.count()).select_from(TaskRecord))
    return {
        "database": db.bind.dialect.name,
        "table": "tasks",
        "row_count": result.scalar_one(),
    }

@app.get("/api/v1/demo/trace-check")
async def demo_trace_check():
    """Prove real distributed traces reached Jaeger, for the live demo dashboard.

    Proxied server-side (not called directly from the browser) because
    Jaeger's own API sends no CORS headers - a browser fetch() straight to
    it would be silently blocked, same class of issue as worker-service's
    /metrics before that was fixed.
    """
    jaeger_url = os.getenv("JAEGER_QUERY_URL", "http://jaeger:16686")
    async with httpx.AsyncClient(timeout=5.0) as client:
        services_resp = await client.get(f"{jaeger_url}/api/services")
        services = services_resp.json().get("data") or []

        recent_spans = 0
        if "api-service" in services:
            traces_resp = await client.get(
                f"{jaeger_url}/api/traces", params={"service": "api-service", "limit": 1}
            )
            traces = traces_resp.json().get("data") or []
            if traces:
                recent_spans = len(traces[0]["spans"])

    return {"traced_services": services, "most_recent_trace_span_count": recent_spans}

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