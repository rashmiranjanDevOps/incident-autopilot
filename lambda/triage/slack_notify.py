"""Posts a message to Slack via an incoming webhook. Copied into both
triage/ and digest/ since it's short and only two functions use it."""
import json
import logging
import urllib.request

import boto3

logger = logging.getLogger()
secrets_client = boto3.client("secretsmanager")

_webhook_url_cache = None


def _get_webhook_url(secret_arn: str) -> str:
    global _webhook_url_cache
    if _webhook_url_cache is None:
        response = secrets_client.get_secret_value(SecretId=secret_arn)
        _webhook_url_cache = response["SecretString"]
    return _webhook_url_cache


def post_to_slack(secret_arn: str, message: str) -> None:
    webhook_url = _get_webhook_url(secret_arn)
    payload = json.dumps({"text": message}).encode("utf-8")
    request = urllib.request.Request(
        webhook_url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        urllib.request.urlopen(request, timeout=5)
    except Exception:
        # Never let a Slack failure crash the pipeline — the DynamoDB
        # audit record is the source of truth; Slack is just a
        # notification on top of it.
        logger.error("Failed to post to Slack", exc_info=True)
