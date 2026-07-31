#!/usr/bin/env bash
# Scenario 3: permission failure (always escalated).
#
# Temporarily attaches an explicit Deny policy to the worker Lambda's
# own IAM role, removing its ability to delete messages from the queue.
# This is a DELIBERATE, REVERSIBLE change made by this script, never
# something the pipeline's own automation would do — see
# docs/SECURITY.md for why permission issues are never auto-remediated.
#
# Expected result within a few minutes:
#   1. Worker Lambda tries to process a message but can't delete it
#      from the queue afterward -> AccessDenied appears in its logs
#   2. The log metric filter turns that into a real metric
#   3. CloudWatch alarm "incident-autopilot-permission-failure" fires
#   4. Triage escalates immediately — permission issues are hard-coded
#      to never auto-remediate, regardless of what rules.json says
#      about anything else
#   5. A 🚨 high-severity Slack escalation and a DynamoDB audit record
#      appear
#
# Usage:
#   ./simulate-permission-failure.sh apply     # break it, on purpose
#   ./simulate-permission-failure.sh revert    # fix it again — DO NOT SKIP THIS

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="incident-autopilot-worker"
POLICY_NAME="incident-autopilot-temporary-demo-deny"
ACTION="${1:-}"

if [ "${ACTION}" != "apply" ] && [ "${ACTION}" != "revert" ]; then
  echo "Usage: $0 [apply|revert]"
  exit 1
fi

if [ "${ACTION}" == "apply" ]; then
  echo "Attaching a temporary Deny policy to ${ROLE_NAME} (sqs:DeleteMessage)..."
  aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "${POLICY_NAME}" \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Deny",
        "Action": "sqs:DeleteMessage",
        "Resource": "*"
      }]
    }' \
    --region "${REGION}"

  QUEUE_URL=$(aws sqs get-queue-url --queue-name incident-autopilot-work-queue --region "${REGION}" --query QueueUrl --output text)
  aws sqs send-message \
    --queue-url "${QUEUE_URL}" \
    --message-body '{"job_id": "permission-failure-demo"}' \
    --region "${REGION}" >/dev/null

  echo "Deny policy attached and a test message sent. The worker will process it"
  echo "successfully but fail to delete it afterward, producing AccessDenied in"
  echo "its logs. Watch for the alarm, then run:"
  echo "  ./simulate-permission-failure.sh revert"
  echo "IMPORTANT: revert this before walking away — the worker can't function at"
  echo "all with this deny policy attached."
else
  echo "Removing the temporary Deny policy from ${ROLE_NAME}..."
  aws iam delete-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "${POLICY_NAME}" \
    --region "${REGION}"
  echo "Reverted. Worker Lambda has its normal permissions back."
fi
