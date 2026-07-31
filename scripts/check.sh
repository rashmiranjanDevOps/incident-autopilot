#!/usr/bin/env bash
# Quick sanity check that the pipeline is actually deployed and reachable.
# Run this after `terraform apply` and before trying any incident
# simulation — if this fails, the simulations will too, for the same
# reason.
#
# Usage: ./check.sh

set -euo pipefail

PREFIX="incident-autopilot"
REGION="${AWS_REGION:-us-east-1}"

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✓ ${description}"
  else
    echo "  ✗ ${description} — NOT FOUND"
    FAILED=1
  fi
}

FAILED=0

echo "Checking incident-autopilot is deployed in ${REGION}..."
echo

check "Work queue exists"       aws sqs get-queue-url --queue-name "${PREFIX}-work-queue" --region "${REGION}"
check "DLQ exists"              aws sqs get-queue-url --queue-name "${PREFIX}-work-queue-dlq" --region "${REGION}"
check "Audit table exists"      aws dynamodb describe-table --table-name "${PREFIX}-audit-log" --region "${REGION}"
check "Worker Lambda exists"    aws lambda get-function --function-name "${PREFIX}-worker" --region "${REGION}"
check "Triage Lambda exists"    aws lambda get-function --function-name "${PREFIX}-triage" --region "${REGION}"
check "Remediate Lambda exists" aws lambda get-function --function-name "${PREFIX}-remediate" --region "${REGION}"
check "Digest Lambda exists"    aws lambda get-function --function-name "${PREFIX}-digest" --region "${REGION}"
check "SNS topic exists"        aws sns get-topic-attributes --topic-arn "arn:aws:sns:${REGION}:$(aws sts get-caller-identity --query Account --output text):${PREFIX}-alarms" --region "${REGION}"

echo
SECRET_STATUS=$(aws secretsmanager get-secret-value --secret-id "${PREFIX}-slack-webhook" --region "${REGION}" --query SecretString --output text 2>/dev/null || echo "UNSET")
if [ "${SECRET_STATUS}" == "UNSET" ] || [ -z "${SECRET_STATUS}" ]; then
  echo "  ⚠ Slack webhook secret exists but has no value set yet — see docs/DEPLOYMENT.md"
else
  echo "  ✓ Slack webhook secret has a value set"
fi

echo
if [ "${FAILED}" -eq 0 ]; then
  echo "All core resources found. Ready for scripts/chaos.sh, simulate-dlq.sh, or simulate-permission-failure.sh."
else
  echo "Some resources are missing — run 'terraform apply' first."
  exit 1
fi
