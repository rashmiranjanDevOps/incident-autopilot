#!/usr/bin/env bash
# Scenario 2: DLQ backlog (escalated, not auto-remediated).
#
# Sends a message with "poison": true, which the worker Lambda is coded
# to always fail on (see lambda/worker/handler.py). After
# max_receive_count (3) failed attempts, SQS's redrive policy moves it
# to the dead-letter queue automatically.
#
# Expected result within a few minutes:
#   1. The message fails 3 times, then lands in incident-autopilot-work-queue-dlq
#   2. CloudWatch alarm "incident-autopilot-dlq-depth" fires
#   3. Triage looks up the rule, sees safe_to_remediate: false
#   4. NO remediation is attempted — blind-redriving an unknown poison
#      message risks an infinite retry loop
#   5. A 🚨 Slack escalation and a DynamoDB audit record appear
#
# Usage: ./simulate-dlq.sh

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
QUEUE_URL=$(aws sqs get-queue-url --queue-name incident-autopilot-work-queue --region "${REGION}" --query QueueUrl --output text)

echo "Sending one poison message..."
aws sqs send-message \
  --queue-url "${QUEUE_URL}" \
  --message-body '{"job_id": "poison-demo", "poison": true}' \
  --region "${REGION}" >/dev/null

echo "Sent. This message will fail 3 times (roughly 90 seconds, given the"
echo "queue's visibility timeout) before landing in the DLQ and firing the"
echo "incident-autopilot-dlq-depth alarm. Check Slack and DynamoDB after that."
echo
echo "To inspect the DLQ directly:"
echo "  aws sqs receive-message --queue-url \$(aws sqs get-queue-url --queue-name incident-autopilot-work-queue-dlq --region ${REGION} --query QueueUrl --output text) --region ${REGION}"
