"""
Worker Lambda — processes messages from the SQS work queue.

Normal messages just get logged. A message with "poison": true always
fails (see scripts/simulate-dlq.sh) — that's how the DLQ demo works.
The throttling demo doesn't touch this file at all; it's just what
happens when scripts/chaos.sh sends more messages than the function's
reserved concurrency can handle.
"""
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


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

    return {"statusCode": 200}
