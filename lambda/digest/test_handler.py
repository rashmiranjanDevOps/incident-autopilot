"""Unit tests for the Digest Lambda. build_summary() is pure and tested
directly; handler() is tested with DynamoDB and Slack mocked out."""
import os
from unittest.mock import patch

os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")
os.environ.setdefault("AUDIT_TABLE_NAME", "incident-autopilot-audit-log")
os.environ.setdefault("SLACK_WEBHOOK_SECRET_ARN", "arn:aws:secretsmanager:us-east-1:123456789012:secret:test")

from handler import build_summary, handler  # noqa: E402


def test_build_summary_with_no_records():
    summary = build_summary([])
    assert "no alarms fired" in summary


def test_build_summary_counts_outcomes():
    records = [
        {"outcome": "auto-remediated"},
        {"outcome": "auto-remediated"},
        {"outcome": "escalated"},
    ]
    summary = build_summary(records)
    assert "3 alarm(s)" in summary
    assert "auto-remediated: 2" in summary
    assert "escalated: 1" in summary


@patch("handler.post_to_slack")
@patch("handler.fetch_recent_records")
def test_handler_posts_the_summary_to_slack(mock_fetch, mock_slack):
    mock_fetch.return_value = [{"outcome": "escalated"}]

    result = handler({}, None)

    assert result == {"statusCode": 200}
    mock_slack.assert_called_once()
    assert "escalated: 1" in mock_slack.call_args[0][1]


@patch("handler.post_to_slack")
@patch("handler.fetch_recent_records")
def test_handler_handles_an_empty_week(mock_fetch, mock_slack):
    mock_fetch.return_value = []

    handler({}, None)

    assert "no alarms fired" in mock_slack.call_args[0][1]
