"""
Digest Lambda — runs weekly via EventBridge, reads the audit table, and
posts a short summary to Slack. Read-only — it can't write to the table.
"""
import logging
import os
import time
from collections import Counter
from decimal import Decimal

import boto3
from boto3.dynamodb.conditions import Attr

from slack_notify import post_to_slack

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["AUDIT_TABLE_NAME"]
SLACK_WEBHOOK_SECRET_ARN = os.environ["SLACK_WEBHOOK_SECRET_ARN"]
LOOKBACK_SECONDS = 7 * 24 * 60 * 60

table = dynamodb.Table(TABLE_NAME)


def fetch_recent_records() -> list:
    """Scans the whole table, filtered by timestamp. A scan is fine
    here — this table is small and append-mostly, and the digest runs
    once a week, not on a hot path. If the table ever grows large
    enough for a scan to be expensive, that's the point to add a GSI
    on a date-bucketed key instead — not before, since that's added
    complexity with no current benefit."""
    cutoff = Decimal(str(time.time() - LOOKBACK_SECONDS))
    records = []

    response = table.scan(FilterExpression=Attr("timestamp").gte(cutoff))
    records.extend(response.get("Items", []))

    while "LastEvaluatedKey" in response:
        response = table.scan(
            FilterExpression=Attr("timestamp").gte(cutoff),
            ExclusiveStartKey=response["LastEvaluatedKey"],
        )
        records.extend(response.get("Items", []))

    return records


def build_summary(records: list) -> str:
    if not records:
        return ":sparkles: *Weekly incident digest:* no alarms fired this week."

    outcomes = Counter(r["outcome"] for r in records)
    lines = [f"*Weekly incident digest — {len(records)} alarm(s):*"]
    for outcome, count in sorted(outcomes.items()):
        lines.append(f"  • {outcome}: {count}")
    return "\n".join(lines)


def handler(event, context):
    records = fetch_recent_records()
    summary = build_summary(records)
    logger.info(summary)
    post_to_slack(SLACK_WEBHOOK_SECRET_ARN, summary)
    return {"statusCode": 200}
