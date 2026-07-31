#!/usr/bin/env bash
# Full teardown, in the right order, plus a cost-leak checklist.
# Modeled on employee-task-infra's teardown guide — the same discipline
# applies here even though this project's steady-state cost is close to
# zero: undeleted resources are still undeleted resources.
#
# Usage: ./cleanup.sh

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"

echo "This will destroy every AWS resource this project created."
read -p "Type 'destroy' to continue: " CONFIRM
if [ "${CONFIRM}" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

# In case scenario 3 was run and left the deny policy attached — Terraform
# can't cleanly delete a role with an extra inline policy it doesn't know
# about, so this is removed first, defensively.
echo "Reverting any leftover demo permission changes (safe to run even if none exist)..."
aws iam delete-role-policy \
  --role-name incident-autopilot-worker \
  --policy-name incident-autopilot-temporary-demo-deny \
  --region "${REGION}" 2>/dev/null || true

echo
echo "Running terraform destroy..."
cd "$(dirname "$0")/../terraform"
terraform destroy

echo
echo "Terraform-managed resources are gone. Manually verify these, since they're"
echo "NOT managed by Terraform and won't be caught by 'terraform destroy':"
echo "  [ ] S3 state bucket (incident-autopilot-tfstate-<account-id>) — only delete"
echo "      this if you're done with the project entirely, it holds your state history"
echo "  [ ] DynamoDB lock table (incident-autopilot-tf-locks) — same caveat"
echo "  [ ] CloudWatch Logs Insights saved queries, if you made any manually"
echo "  [ ] Any manual Slack webhook you created — revoke it in Slack's app settings"
echo
echo "Done. Nothing in this project has an ongoing cost once the above is confirmed."
