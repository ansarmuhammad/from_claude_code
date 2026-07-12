"""
Unit tests for Worker Service Celery tasks
"""
from unittest.mock import patch

import pytest

from worker import generate_report, process_item, send_notification


@patch("worker.time.sleep", return_value=None)
def test_process_item_returns_processed_status(mock_sleep):
    result = process_item("item-1", {"name": "widget"})
    assert result["status"] == "processed"
    mock_sleep.assert_called_once()


@patch("worker.time.sleep", return_value=None)
def test_process_item_includes_item_id(mock_sleep):
    result = process_item("item-42")
    assert result["item_id"] == "item-42"


@patch("worker.time.sleep", return_value=None)
def test_process_item_defaults_empty_payload(mock_sleep):
    result = process_item("item-2", payload=None)
    assert result["payload"] == {}


@patch("worker.time.sleep", return_value=None)
def test_process_item_preserves_payload(mock_sleep):
    payload = {"category": "electronics", "qty": 5}
    result = process_item("item-3", payload)
    assert result["payload"] == payload


@patch("worker.time.sleep", return_value=None)
def test_send_notification_returns_sent_status(mock_sleep):
    result = send_notification("user@example.com", "Hello!")
    assert result["status"] == "sent"
    mock_sleep.assert_called_once()


@patch("worker.time.sleep", return_value=None)
def test_send_notification_includes_recipient_and_message(mock_sleep):
    result = send_notification("user@example.com", "Your order shipped")
    assert result["recipient"] == "user@example.com"
    assert result["message"] == "Your order shipped"


@patch("worker.time.sleep", return_value=None)
def test_generate_report_returns_completed_status(mock_sleep):
    result = generate_report("sales")
    assert result["status"] == "completed"
    mock_sleep.assert_called_once()


@patch("worker.time.sleep", return_value=None)
def test_generate_report_defaults_empty_filters(mock_sleep):
    result = generate_report("inventory", filters=None)
    assert result["filters"] == {}


@patch("worker.time.sleep", return_value=None)
def test_generate_report_preserves_filters(mock_sleep):
    filters = {"region": "us-east", "year": 2026}
    result = generate_report("inventory", filters)
    assert result["filters"] == filters
    assert result["report_type"] == "inventory"
