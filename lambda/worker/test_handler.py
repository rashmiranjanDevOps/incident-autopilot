"""Unit tests for the worker Lambda. No AWS calls to mock — this
function's only inputs are the SQS event and the message body, so
plain pytest is enough, no moto/boto3 mocking needed."""
import json

import pytest

from handler import handler, process_message


def _sqs_event(*bodies):
    return {"Records": [{"body": json.dumps(b)} for b in bodies]}


def test_process_message_succeeds_for_a_normal_job(caplog):
    caplog.set_level("INFO")
    process_message({"job_id": "job-1"})
    assert "processed successfully" in caplog.text


def test_process_message_raises_for_a_poison_message():
    with pytest.raises(RuntimeError, match="poison message"):
        process_message({"job_id": "job-2", "poison": True})


def test_handler_processes_all_records_in_the_batch():
    event = _sqs_event({"job_id": "job-1"}, {"job_id": "job-2"})
    result = handler(event, None)
    assert result == {"statusCode": 200}


def test_handler_raises_on_a_poison_message_in_the_batch():
    event = _sqs_event({"job_id": "job-1"}, {"job_id": "job-2", "poison": True})
    with pytest.raises(RuntimeError):
        handler(event, None)


def test_handler_raises_on_malformed_body():
    event = {"Records": [{"body": "not json"}]}
    with pytest.raises(json.JSONDecodeError):
        handler(event, None)


def test_handler_with_no_records_returns_success():
    assert handler({"Records": []}, None) == {"statusCode": 200}
