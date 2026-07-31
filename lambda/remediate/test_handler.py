"""Unit tests for the Remediate Lambda. Mocks the boto3 Lambda client —
these tests should never make a real AWS call."""
import os
from unittest.mock import MagicMock, patch

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("WORKER_FUNCTION_NAME", "incident-autopilot-worker")
os.environ.setdefault("MAX_RESERVED_CONCURRENCY", "10")
os.environ.setdefault("CONCURRENCY_INCREMENT", "5")

from handler import handler, increase_worker_concurrency  # noqa: E402


@patch("handler.lambda_client")
def test_increase_worker_concurrency_raises_by_the_increment(mock_client):
    mock_client.get_function_concurrency.return_value = {"ReservedConcurrentExecutions": 2}

    result = increase_worker_concurrency({})

    mock_client.put_function_concurrency.assert_called_once_with(
        FunctionName="incident-autopilot-worker",
        ReservedConcurrentExecutions=7,
    )
    assert result["success"] is True
    assert "2 to 7" in result["detail"]


@patch("handler.lambda_client")
def test_increase_worker_concurrency_never_exceeds_the_cap(mock_client):
    mock_client.get_function_concurrency.return_value = {"ReservedConcurrentExecutions": 9}

    result = increase_worker_concurrency({})

    mock_client.put_function_concurrency.assert_called_once_with(
        FunctionName="incident-autopilot-worker",
        ReservedConcurrentExecutions=10,
    )
    assert result["success"] is True


@patch("handler.lambda_client")
def test_increase_worker_concurrency_no_op_when_already_at_cap(mock_client):
    mock_client.get_function_concurrency.return_value = {"ReservedConcurrentExecutions": 10}

    result = increase_worker_concurrency({})

    mock_client.put_function_concurrency.assert_not_called()
    assert "no change made" in result["detail"]


def test_handler_refuses_an_action_not_on_the_whitelist():
    result = handler({"action": "delete_everything"}, None)
    assert result["success"] is False
    assert "not whitelisted" in result["detail"]


def test_handler_refuses_a_missing_action():
    result = handler({}, None)
    assert result["success"] is False


@patch("handler.lambda_client")
def test_handler_dispatches_to_the_registered_action(mock_client):
    mock_client.get_function_concurrency.return_value = {"ReservedConcurrentExecutions": 2}

    result = handler({"action": "increase_worker_concurrency", "alarm_name": "test"}, None)

    assert result["success"] is True


@patch("handler.lambda_client")
def test_handler_returns_failure_if_the_action_itself_raises(mock_client):
    mock_client.get_function_concurrency.side_effect = Exception("boto3 exploded")

    result = handler({"action": "increase_worker_concurrency"}, None)

    assert result["success"] is False
    assert "boto3 exploded" in result["detail"]
