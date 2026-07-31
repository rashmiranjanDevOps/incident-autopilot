"""
Unit tests for the Triage Lambda.

triage_one_alarm() is pure decision logic with no AWS calls, so it's
tested directly and thoroughly. handler() is tested end-to-end with
boto3 and Slack mocked out — these tests should never make a real AWS
or network call.
"""
import json
import os
from unittest.mock import patch

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AUDIT_TABLE_NAME", "incident-autopilot-audit-log")
os.environ.setdefault("REMEDIATE_FUNCTION_NAME", "incident-autopilot-remediate")
os.environ.setdefault("SLACK_WEBHOOK_SECRET_ARN", "arn:aws:secretsmanager:us-east-1:123456789012:secret:test")

from handler import handler, parse_alarm, triage_one_alarm  # noqa: E402


def _sns_event(alarm_name: str, reason: str = "threshold breached") -> dict:
    message = json.dumps({"AlarmName": alarm_name, "NewStateReason": reason})
    return {"Records": [{"Sns": {"Message": message}}]}


def test_parse_alarm_reads_the_cloudwatch_payload():
    message = json.dumps({"AlarmName": "some-alarm", "NewStateReason": "why"})
    assert parse_alarm(message) == {"AlarmName": "some-alarm", "NewStateReason": "why"}


def test_known_safe_alarm_routes_to_remediate():
    decision = triage_one_alarm({"AlarmName": "incident-autopilot-worker-throttling"})
    assert decision["path"] == "remediate"
    assert decision["action"] == "increase_worker_concurrency"


def test_dlq_alarm_routes_to_escalate_not_remediate():
    decision = triage_one_alarm({"AlarmName": "incident-autopilot-dlq-depth"})
    assert decision["path"] == "escalate"
    assert decision["outcome"] == "escalated"


def test_permission_failure_alarm_always_escalates():
    decision = triage_one_alarm({"AlarmName": "incident-autopilot-permission-failure"})
    assert decision["path"] == "escalate"
    assert "high" in decision["message"]


def test_unrecognized_alarm_escalates_instead_of_guessing():
    decision = triage_one_alarm({"AlarmName": "some-alarm-with-no-rule"})
    assert decision["path"] == "escalate"
    assert "No matching rule" in decision["detail"]


@patch("handler.post_to_slack")
@patch("handler.table")
@patch("handler.lambda_client")
def test_handler_invokes_remediation_for_a_safe_alarm(mock_lambda, mock_table, mock_slack):
    mock_lambda.invoke.return_value = {
        "Payload": _FakePayload(json.dumps({"success": True, "detail": "raised concurrency"}))
    }

    result = handler(_sns_event("incident-autopilot-worker-throttling"), None)

    assert result == {"statusCode": 200}
    mock_lambda.invoke.assert_called_once()
    _, kwargs = mock_lambda.invoke.call_args
    payload = json.loads(kwargs["Payload"])
    assert payload["action"] == "increase_worker_concurrency"

    mock_table.put_item.assert_called_once()
    written_item = mock_table.put_item.call_args.kwargs["Item"]
    assert written_item["outcome"] == "auto-remediated"

    mock_slack.assert_called_once()
    assert "Auto-remediated" in mock_slack.call_args[0][1]


@patch("handler.post_to_slack")
@patch("handler.table")
@patch("handler.lambda_client")
def test_handler_never_invokes_remediation_for_dlq_alarm(mock_lambda, mock_table, mock_slack):
    result = handler(_sns_event("incident-autopilot-dlq-depth"), None)

    assert result == {"statusCode": 200}
    mock_lambda.invoke.assert_not_called()

    mock_table.put_item.assert_called_once()
    written_item = mock_table.put_item.call_args.kwargs["Item"]
    assert written_item["outcome"] == "escalated"

    mock_slack.assert_called_once()
    assert "Escalation" in mock_slack.call_args[0][1]


@patch("handler.post_to_slack")
@patch("handler.table")
@patch("handler.lambda_client")
def test_handler_escalates_an_unrecognized_alarm_without_guessing(mock_lambda, mock_table, mock_slack):
    handler(_sns_event("totally-unknown-alarm"), None)

    mock_lambda.invoke.assert_not_called()
    written_item = mock_table.put_item.call_args.kwargs["Item"]
    assert written_item["outcome"] == "escalated"
    assert "Unrecognized" in mock_slack.call_args[0][1]


class _FakePayload:
    """Minimal stand-in for the StreamingBody boto3 returns from
    lambda_client.invoke()['Payload'] — real code calls .read() on it."""

    def __init__(self, data: str):
        self._data = data.encode("utf-8")

    def read(self):
        return self._data
