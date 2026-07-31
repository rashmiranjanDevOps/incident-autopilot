# Runbook

What a human does for each of the three incident types this pipeline knows about. If you get paged (Slack-messaged) by this system, start here.

## incident-autopilot-worker-throttling — auto-remediated, informational

**What you'll see:** a ✅ Slack message saying the worker's reserved concurrency was raised, with the before/after numbers.

**What to do:** nothing, usually — this is a status update, not a page. If you see this repeatedly in a short window, the increment (default +5, capped at 10) may not be keeping up with real load; consider raising `worker_max_reserved_concurrency` in `terraform/variables.tf` and re-applying.

**How to check it yourself:** `aws lambda get-function-concurrency --function-name incident-autopilot-worker`

## incident-autopilot-dlq-depth — always escalated

**What you'll see:** a 🚨 Slack message with the alarm name and a note to check the DLQ.

**What to do:**
1. Inspect the message(s) without removing them:
   ```
   aws sqs receive-message \
     --queue-url $(aws sqs get-queue-url --queue-name incident-autopilot-work-queue-dlq --query QueueUrl --output text) \
     --visibility-timeout 0
   ```
2. Figure out why it failed — check `/aws/lambda/incident-autopilot-worker` in CloudWatch Logs for the job ID.
3. If it's safe to retry (transient issue, bug now fixed), redrive it back to the source queue:
   ```
   aws sqs start-message-move-task \
     --source-arn <dlq-arn> \
     --destination-arn <work-queue-arn>
   ```
4. If it's not safe to retry (bad data, will fail forever), delete it from the DLQ deliberately, and note why in the audit trail if you're tracking incidents elsewhere.

**Why this isn't automated:** redriving a message the pipeline doesn't understand risks an infinite retry loop — it would just fail three more times and land right back in the DLQ. A human confirming "yes, this is actually fixed now" is the safety check.

## incident-autopilot-permission-failure — always escalated, high severity

**What you'll see:** a 🚨 high-severity Slack message, distinct in tone from the routine digest.

**What to do:**
1. Check what changed — `aws iam list-role-policies --role-name incident-autopilot-worker` and compare against `terraform/modules/lambda-worker/main.tf`.
2. If this was `scripts/simulate-permission-failure.sh` and you forgot to revert it: `./scripts/simulate-permission-failure.sh revert`.
3. If it's a real permission drift (someone manually changed the role, or a Terraform apply removed a needed permission), fix the Terraform module and re-apply — don't patch IAM by hand, or the next `terraform apply` will just undo your fix.

**Why this is never auto-remediated:** automatically "fixing" a permission problem is itself a security-relevant action — it needs a human to confirm the change was intentional and correct, not just plausible.

## Weekly digest

Every Sunday (default schedule), the Digest Lambda posts a summary of the past 7 days: how many alarms fired, broken down by outcome (`auto-remediated`, `escalated`, `remediation-failed`). No action needed — it's a health check on the pipeline itself, and a good thing to screenshot for interviews.
