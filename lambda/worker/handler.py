"""
Worker Lambda — processes messages from the SQS work queue.

Normal messages just get logged. A message with "poison": true always
fails (see scripts/simulate-dlq.sh) — that's how the DLQ demo works.
The throttling demo doesn't touch this file at all; it's just what
happens when scripts/chaos.sh sends more messages than the function's
reserved concurrency can handle.

Message deletion is explicit (see handler(), below) rather than left to
Lambda's implicit delete-on-success behavior. Implicit deletion happens
in AWS's own SQS poller, outside this function's execution — so if the
worker's role ever lost sqs:DeleteMessage, that failure would happen
invisibly, with nothing in these logs to show it. Deleting explicitly
means a permission failure here actually gets logged, which is what the
"permission failure" alarm's metric filter watches for — see
docs/RUNBOOK.md and scripts/simulate-permission-failure.sh.
"""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

QUEUE_URL = os.environ.get("QUEUE_URL", "")


def process_message(body: dict) -> None:
    """The actual 'work'. In a real system this would do something —
    here it just logs, which is enough to prove the pipeline works."""
    job_id = body.get("job_id", "unknown")
    logger.info("Processing job %s", job_id)

    if body.get("poison"):
        raise RuntimeError(f"Job {job_id} is a poison message (fails every time, by design)")

    logger.info("Job %s processed successfully", job_id)


def handler(event, context):
    """SQS trigger. Raising an exception for a message causes SQS to
    retry it, and after max_receive_count retries, redrive it to the
    DLQ — see terraform/modules/core for that policy."""
    for record in event.get("Records", []):
        raw_body = record.get("body", "")
        try:
            body = json.loads(raw_body)
        except (json.JSONDecodeError, TypeError):
            logger.error("Could not parse message body: %s", raw_body)
            raise

        process_message(body)

        receipt_handle = record.get("receiptHandle")
        if receipt_handle and QUEUE_URL:
            try:
                sqs = boto3.client("sqs")
                sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt_handle)
            except Exception:
                logger.error("AccessDenied deleting message from queue", exc_info=True)

    return {"statusCode": 200}