"""
Triage Lambda — decides what to do about an alarm. Triggered by SNS.

Looks the alarm up in rules.json. If it's marked safe, invokes the
Remediate Lambda. If not (or there's no matching rule), posts a Slack
message instead and does nothing automated. Either way, writes one
record to the audit table.
"""
import json
import logging
import os
import time
from decimal import Decimal

import boto3

from slack_notify import post_to_slack

logger = logging.getLogger()
logger.setLevel(logging.INFO)

lambda_client = boto3.client("lambda")
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["AUDIT_TABLE_NAME"]
REMEDIATE_FUNCTION_NAME = os.environ["REMEDIATE_FUNCTION_NAME"]
SLACK_WEBHOOK_SECRET_ARN = os.environ["SLACK_WEBHOOK_SECRET_ARN"]

table = dynamodb.Table(TABLE_NAME)

with open(os.path.join(os.path.dirname(__file__), "rules.json")) as f:
    RULES = json.load(f)


def parse_alarm(sns_message: str) -> dict:
    """CloudWatch alarm notifications arrive as a JSON string inside the
    SNS message body — this just gets it back into a dict."""
    return json.loads(sns_message)


def invoke_remediation(action: str, alarm_name: str) -> dict:
    response = lambda_client.invoke(
        FunctionName=REMEDIATE_FUNCTION_NAME,
        InvocationType="RequestResponse",
        Payload=json.dumps({"action": action, "alarm_name": alarm_name}),
    )
    return json.loads(response["Payload"].read())


def write_audit_record(alarm_name: str, rule: dict, outcome: str, detail: str) -> None:
    table.put_item(
        Item={
            "alarm_name": alarm_name,
            "timestamp": Decimal(str(time.time())),
            "severity": rule.get("severity", "unknown"),
            "safe_to_remediate": rule.get("safe_to_remediate", False),
            "outcome": outcome,
            "detail": detail,
        }
    )


def triage_one_alarm(alarm: dict) -> dict:
    """Pure decision logic, pulled out of handler() so it's directly
    unit-testable without needing to mock SNS event shapes for every
    test case. Returns what happened, for the caller to notify/log."""
    alarm_name = alarm.get("AlarmName", "unknown-alarm")
    reason = alarm.get("NewStateReason", "")
    rule = RULES.get(alarm_name)

    if rule is None:
        # No rule for this alarm at all — always escalate. Guessing at
        # an unknown alarm is exactly what this project's design is
        # built to avoid.
        return {
            "alarm_name": alarm_name,
            "rule": {},
            "path": "escalate",
            "message": f":grey_question: *Unrecognized alarm:* {alarm_name}\n{reason}",
            "outcome": "escalated",
            "detail": "No matching rule in rules.json",
        }

    if rule["safe_to_remediate"]:
        return {
            "alarm_name": alarm_name,
            "rule": rule,
            "path": "remediate",
            "action": rule["action"],
        }

    return {
        "alarm_name": alarm_name,
        "rule": rule,
        "path": "escalate",
        "message": (
            f":rotating_light: *Escalation — {rule['severity']}:* {alarm_name}\n"
            f"{rule['description']}\nSee docs/RUNBOOK.md for how to respond."
        ),
        "outcome": "escalated",
        "detail": rule["description"],
    }


def handler(event, context):
    for record in event["Records"]:
        alarm = parse_alarm(record["Sns"]["Message"])
        decision = triage_one_alarm(alarm)
        logger.info("Triage decision for %s: %s", decision["alarm_name"], decision["path"])

        if decision["path"] == "remediate":
            result = invoke_remediation(decision["action"], decision["alarm_name"])
            success = result.get("success", False)
            message = (
                f":white_check_mark: *Auto-remediated:* {decision['alarm_name']}\n{result.get('detail')}"
                if success
                else f":x: *Remediation attempt failed:* {decision['alarm_name']}\n{result.get('detail')}"
            )
            post_to_slack(SLACK_WEBHOOK_SECRET_ARN, message)
            write_audit_record(
                decision["alarm_name"],
                decision["rule"],
                "auto-remediated" if success else "remediation-failed",
                result.get("detail", ""),
            )
        else:
            post_to_slack(SLACK_WEBHOOK_SECRET_ARN, decision["message"])
            write_audit_record(
                decision["alarm_name"], decision["rule"], decision["outcome"], decision["detail"]
            )

    return {"statusCode": 200}
