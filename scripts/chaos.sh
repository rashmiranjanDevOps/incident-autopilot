#!/usr/bin/env bash
# Scenario 1: worker throttling (auto-remediated).
#
# Sends a burst of ordinary messages — no "poison" flag, nothing wrong
# with them individually — fast enough to exceed the worker Lambda's
# reserved concurrency (2, by default). This is a REAL AWS-level
# throttling condition, not a simulated one: Lambda actually can't run
# enough concurrent instances to keep up, which is exactly the kind of
# capacity problem this project's auto-remediation is designed for.
#
# Expected result within a minute or two:
#   1. CloudWatch alarm "incident-autopilot-worker-throttling" fires
#   2. SNS notifies the Triage Lambda
#   3. Triage looks up the rule, sees safe_to_remediate: true
#   4. Remediate Lambda raises the worker's reserved concurrency
#   5. A ✅ Slack message and a DynamoDB audit record appear
#
# Usage: ./chaos.sh [message-count]

set -euo pipefail

COUNT="${1:-50}"
REGION="${AWS_REGION:-us-east-1}"
QUEUE_URL=$(aws sqs get-queue-url --queue-name incident-autopilot-work-queue --region "${REGION}" --query QueueUrl --output text)

echo "Sending ${COUNT} messages as fast as possible to trigger worker throttling..."
echo "Queue: ${QUEUE_URL}"
echo

for i in $(seq 1 "${COUNT}"); do
  aws sqs send-message \
    --queue-url "${QUEUE_URL}" \
    --message-body "{\"job_id\": \"chaos-${i}\"}" \
    --region "${REGION}" >/dev/null &
done
wait

echo "Sent. Watch for the incident-autopilot-worker-throttling alarm in CloudWatch"
echo "(usually fires within 1-2 minutes), then check your Slack channel and the"
echo "incident-autopilot-audit-log DynamoDB table for the result."
