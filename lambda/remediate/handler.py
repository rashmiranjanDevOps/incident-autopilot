"""
Remediate Lambda — the only function that's allowed to change anything.
Right now it can do exactly one thing: raise the worker Lambda's reserved
concurrency, safely and by a small amount at a time. Its IAM role only
grants the two API calls that action needs, on that one function.
"""
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

lambda_client = boto3.client("lambda")

WORKER_FUNCTION_NAME = os.environ["WORKER_FUNCTION_NAME"]
MAX_RESERVED_CONCURRENCY = int(os.environ.get("MAX_RESERVED_CONCURRENCY", "10"))
CONCURRENCY_INCREMENT = int(os.environ.get("CONCURRENCY_INCREMENT", "5"))


def increase_worker_concurrency(payload: dict) -> dict:
    """Raises reserved concurrency by a fixed amount, capped at
    MAX_RESERVED_CONCURRENCY. Never removes the cap entirely."""
    current = lambda_client.get_function_concurrency(FunctionName=WORKER_FUNCTION_NAME)
    current_limit = current.get("ReservedConcurrentExecutions") or 0

    new_limit = min(current_limit + CONCURRENCY_INCREMENT, MAX_RESERVED_CONCURRENCY)

    if new_limit == current_limit:
        return {
            "success": True,
            "detail": f"Already at the maximum allowed concurrency ({MAX_RESERVED_CONCURRENCY}), no change made",
        }

    lambda_client.put_function_concurrency(
        FunctionName=WORKER_FUNCTION_NAME,
        ReservedConcurrentExecutions=new_limit,
    )

    return {
        "success": True,
        "detail": f"Raised worker reserved concurrency from {current_limit} to {new_limit}",
    }


def handler(event, context):
    action = event.get("action")
    logger.info("Remediation requested: %s (alarm: %s)", action, event.get("alarm_name"))

    # Only one action exists today, so a plain if-check is enough — this
    # can turn into a dict of actions if a second one ever gets added.
    if action != "increase_worker_concurrency":
        logger.warning("Action '%s' is not whitelisted — refusing", action)
        return {"success": False, "detail": f"Action '{action}' is not whitelisted"}

    try:
        result = increase_worker_concurrency(event)
        logger.info("Remediation result: %s", result)
        return result
    except Exception as exc:
        logger.error("Remediation failed: %s", exc, exc_info=True)
        return {"success": False, "detail": str(exc)}
