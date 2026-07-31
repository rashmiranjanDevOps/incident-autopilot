# Deployment guide

## Prerequisites

- An AWS account, with the AWS CLI configured with credentials that can create IAM roles, S3 buckets, DynamoDB tables, SQS queues, Lambda functions, SNS topics, EventBridge rules, Secrets Manager secrets, and CloudWatch alarms/log groups
- Terraform >= 1.6.0
- Python 3.12 (only needed to run tests locally, not to deploy)
- A Slack workspace where you can add an incoming webhook
- This repo pushed to your own GitHub account

## First-time setup (run once, locally)

**1. Bootstrap the Terraform state backend**
```bash
./scripts/bootstrap-backend.sh us-east-1
```
Creates an S3 bucket and a DynamoDB table via plain AWS CLI calls — Terraform can't create the bucket its own state lives in.

**2. Point Terraform at that backend**
Update `terraform/backend.hcl` with the bucket name the script printed.

**3. First apply — has to run locally**
GitHub Actions needs the OIDC role to exist before it can talk to AWS at all, so the very first apply can't go through CI.
```bash
cd terraform
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```
This creates everything: the OIDC role, all four Lambda functions, the queue and DLQ, the audit table, the SNS topic, the alarms, and the (empty) Slack secret.

**4. Set the Slack webhook value**
Terraform creates the secret but doesn't put a real value in it (see `SECURITY.md`). Add an incoming webhook in Slack, then:
```bash
aws secretsmanager put-secret-value \
  --secret-id incident-autopilot-slack-webhook \
  --secret-string "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

**5. Wire up CI**
Take the `github_actions_role_arn` output from step 3 and add it as a GitHub repo secret named `AWS_GITHUB_ACTIONS_ROLE_ARN`. From here on, pushes to `main` deploy automatically; pull requests just get a plan.

**6. Check it worked**
```bash
./scripts/check.sh
```

## Ongoing deployments

Push to `main`. CI runs all four Lambdas' tests first, then `terraform plan`, then `terraform apply` — a failing test blocks the deploy before Terraform even runs.

## Updating Lambda code

Edit the file under `lambda/<function>/` and push. Terraform re-zips the source on every plan and only redeploys the function(s) that actually changed — no manual packaging step.

---

## Cost

At demo-level usage — a few dozen messages per test run, a handful of incident simulations, one weekly digest — this runs at or near free-tier levels on a personal AWS account.

| Resource | Expected cost at this scale |
|---|---|
| Lambda (×4) | Free tier covers this easily |
| SQS (queue + DLQ) | Free tier covers this easily |
| DynamoDB (on-demand) | Fractions of a cent |
| SNS | Free tier covers this easily |
| CloudWatch Alarms | 3 alarms × ~$0.10/month ≈ $0.30/month |
| CloudWatch Logs | Negligible — 14-day retention keeps it bounded |
| EventBridge | Effectively free at 1 run/week |
| Secrets Manager | ~$0.40/month — the one real fixed cost here |
| S3 (Terraform state) | Negligible |

Secrets Manager is really the only fixed monthly cost; everything else scales with usage and stays close to free at this scale. A few small choices keep it that way: DynamoDB is on-demand instead of provisioned, logs only stick around for 14 days, and there's nothing always-on running in the background (no NAT gateway, no database server).

Run `scripts/cleanup.sh` when you're done demoing so nothing keeps costing money after the fact.

## Cleaning up / teardown

Run `./scripts/cleanup.sh` — it handles the one ordering issue below and asks for confirmation before destroying anything.

**Why a plain `terraform destroy` can fail:** if `scripts/simulate-permission-failure.sh apply` was run and never reverted, the worker's IAM role has an extra policy attached that Terraform doesn't know about, and it can't delete a role with an attached policy it doesn't manage. `cleanup.sh` removes that policy first (it's a no-op if it's not there), so this doesn't come up.

**What Terraform destroys automatically:** every Lambda and its role, the queue and DLQ, the audit table, the SNS topic, all three alarms and the log metric filter, the EventBridge rule, the Slack secret, and the GitHub Actions OIDC role.

**What Terraform doesn't touch:**
- The S3 state bucket and DynamoDB lock table — Terraform can't delete the bucket its own state lives in mid-run, so these need a manual `aws s3 rb ... --force` and `aws dynamodb delete-table ...` once you're fully done
- The Slack webhook itself — Terraform deletes the *secret*, but revoke the webhook in Slack's app settings too, or it'll keep accepting requests that go nowhere

**Double-checking nothing's left running:**
```bash
aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'incident-autopilot')].FunctionName"
aws sqs list-queues --queue-name-prefix incident-autopilot
aws dynamodb list-tables --query "TableNames[?starts_with(@, 'incident-autopilot')]"
```
All three should come back empty once teardown's done (aside from the state bucket/lock table, if you kept those on purpose).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform init` fails with a backend error | `terraform/backend.hcl` still has the placeholder bucket name | Run `scripts/bootstrap-backend.sh`, then update `backend.hcl` |
| First `terraform apply` fails with an OIDC/assume-role error in CI | The OIDC role doesn't exist yet | The first apply has to run locally — see step 3 above |
| CI fails at `terraform apply` with `AccessDenied` | The GitHub Actions role's policy doesn't cover a resource you added | Check `terraform/main.tf`'s `github_actions_project` policy — new AWS services need a matching statement |
| `chaos.sh` doesn't trigger the throttling alarm | Messages processed too slowly to overlap, or concurrency was already raised by an earlier remediation | Check `aws lambda get-function-concurrency --function-name incident-autopilot-worker` — if it's already near the cap, that's actually the remediation from last time working |
| `simulate-dlq.sh` message never reaches the DLQ | `max_receive_count` was changed, or the visibility timeout is longer than expected | Check `terraform/modules/core/variables.tf`; the message needs to fail exactly `max_receive_count` times |
| No Slack messages from any scenario | The webhook secret has no value, or the wrong value | `aws secretsmanager get-secret-value --secret-id incident-autopilot-slack-webhook` — if empty, see step 4 above |
| Triage Lambda errors with `KeyError` reading `rules.json` | An alarm name in AWS doesn't exactly match a key in `lambda/triage/rules.json` | Compare `terraform/modules/alarms/main.tf`'s `alarm_name` values against the JSON keys character-for-character |
| Worker stuck failing after `simulate-permission-failure.sh apply` | Forgot to revert | Run `./scripts/simulate-permission-failure.sh revert` |
| `terraform destroy` fails partway through | Usually the leftover deny-policy from the permission-failure scenario | `scripts/cleanup.sh` handles this automatically |
