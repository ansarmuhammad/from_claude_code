"""
Worker Service - Celery Background Worker
Part of CI/CD Practice Project
"""
import logging
import os
import threading
import time
from wsgiref.simple_server import make_server

from celery import Celery
from celery.signals import task_failure, task_prerun, task_success, worker_ready
from opentelemetry.instrumentation.celery import CeleryInstrumentor
from pythonjsonlogger import jsonlogger
from prometheus_client import Counter, Histogram, make_wsgi_app

from tracing import setup_tracing

# JSON logging configuration
logger = logging.getLogger("worker-service")
logger.setLevel(logging.INFO)
log_handler = logging.StreamHandler()
log_handler.setFormatter(jsonlogger.JsonFormatter("%(asctime)s %(name)s %(levelname)s %(message)s"))
logger.addHandler(log_handler)

setup_tracing("worker-service")
CeleryInstrumentor().instrument()

# Celery configuration from env vars
CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", "redis://localhost:6379/0")
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", "redis://localhost:6379/1")

celery_app = Celery(
    "worker_service",
    broker=CELERY_BROKER_URL,
    backend=CELERY_RESULT_BACKEND,
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
)

# Prometheus metrics
task_count = Counter(
    "worker_tasks_total", "Total number of Celery tasks processed", ["task_name", "status"]
)
task_duration = Histogram(
    "worker_task_duration_seconds", "Task execution duration in seconds", ["task_name"]
)

_task_start_times = {}


@task_prerun.connect
def on_task_prerun(task_id=None, task=None, **kwargs):
    _task_start_times[task_id] = time.time()


@task_success.connect
def on_task_success(sender=None, **kwargs):
    task_name = sender.name if sender else "unknown"
    task_id = kwargs.get("task_id")
    start_time = _task_start_times.pop(task_id, None)
    if start_time is not None:
        task_duration.labels(task_name=task_name).observe(time.time() - start_time)
    task_count.labels(task_name=task_name, status="success").inc()


@task_failure.connect
def on_task_failure(sender=None, **kwargs):
    task_name = sender.name if sender else "unknown"
    task_count.labels(task_name=task_name, status="failure").inc()


def _cors_enabled_metrics_app(environ, start_response):
    # prometheus_client's own start_http_server() sends no CORS headers, which
    # silently blocks browser-based fetch() reads (curl doesn't care, so this
    # only shows up when something in a real browser tries to read /metrics).
    metrics_app = make_wsgi_app()

    def start_response_with_cors(status, headers, exc_info=None):
        headers = headers + [("Access-Control-Allow-Origin", "*")]
        return start_response(status, headers, exc_info)

    return metrics_app(environ, start_response_with_cors)


@worker_ready.connect
def on_worker_ready(**kwargs):
    metrics_port = int(os.getenv("METRICS_PORT", "9100"))
    httpd = make_server("", metrics_port, _cors_enabled_metrics_app)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    logger.info("Prometheus metrics server started", extra={"port": metrics_port})


@celery_app.task(name="worker.process_item")
def process_item(item_id: str, payload: dict = None) -> dict:
    """Simulate processing an item created via the API service."""
    logger.info("Processing item", extra={"item_id": item_id, "payload": payload})
    time.sleep(2)
    result = {"item_id": item_id, "status": "processed", "payload": payload or {}}
    logger.info("Finished processing item", extra={"item_id": item_id})
    return result


@celery_app.task(name="worker.send_notification")
def send_notification(recipient: str, message: str) -> dict:
    """Simulate sending a notification to a recipient."""
    logger.info("Sending notification", extra={"recipient": recipient, "notification_message": message})
    time.sleep(1)
    result = {"recipient": recipient, "message": message, "status": "sent"}
    logger.info("Notification sent", extra={"recipient": recipient})
    return result


@celery_app.task(name="worker.generate_report")
def generate_report(report_type: str, filters: dict = None) -> dict:
    """Simulate generating a report of a given type."""
    logger.info("Generating report", extra={"report_type": report_type, "filters": filters})
    time.sleep(3)
    result = {
        "report_type": report_type,
        "filters": filters or {},
        "status": "completed",
        "rows": 0,
    }
    logger.info("Report generated", extra={"report_type": report_type})
    return result


if __name__ == "__main__":
    celery_app.start()
