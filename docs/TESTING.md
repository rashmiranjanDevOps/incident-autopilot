# Testing guide

## Unit tests

Every Lambda has its own self-contained test file, run independently (matching how each is packaged and deployed independently):

```bash
cd lambda/worker    && python -m pytest -v
cd lambda/remediate && python -m pytest -v
cd lambda/triage    && python -m pytest -v
cd lambda/digest    && python -m pytest -v
```

25 tests total. What's covered, and deliberately what isn't:

| Function | Covered | Not covered (honestly) |
|---|---|---|
| Worker | Normal processing, poison-message failure, malformed input, batch handling | Real SQS batching edge cases (partial batch failures) — out of scope for a demo queue |
| Remediate | Concurrency increment math, the hard cap, no-op when already capped, unknown-action refusal, exception handling | Doesn't test against a real Lambda API — mocked `boto3` throughout |
| Triage | All three rule-lookup paths (safe/unsafe/unknown), full handler flow for each, exact DynamoDB write content, exact Slack message content | Doesn't test malformed SNS payloads — CloudWatch's alarm-to-SNS format is fixed, so this wasn't prioritized |
| Digest | Summary formatting (empty week, multiple outcomes), handler wiring | Doesn't test DynamoDB pagination beyond one page — acceptable for this table's expected size |

Triage has the most tests because it's the decision point — if it's wrong, either something unsafe gets auto-remediated or something safe gets escalated for no reason, so I wanted to be extra sure that logic was right.

## Testing the deployed pipeline

Unit tests prove the code is correct in isolation. They don't prove the alarms are wired up, the IAM permissions are actually sufficient, or Slack messages actually arrive — that's what the incident simulations are for.

```bash
./scripts/check.sh                          # confirms everything is deployed
./scripts/chaos.sh                          # scenario 1: throttling -> auto-remediated
./scripts/simulate-dlq.sh                   # scenario 2: DLQ -> escalated
./scripts/simulate-permission-failure.sh apply   # scenario 3: permission -> escalated
./scripts/simulate-permission-failure.sh revert  # always run this after apply
```

Each is documented in detail, including exactly what to expect, in `docs/RUNBOOK.md`.

## What "done" looks like for a manual test pass

- [ ] All 25 unit tests pass
- [ ] `./scripts/check.sh` shows every resource deployed
- [ ] Scenario 1 produces a ✅ Slack message and an `auto-remediated` DynamoDB record
- [ ] Scenario 2 produces a 🚨 Slack message and an `escalated` DynamoDB record, and the message is actually visible in the DLQ
- [ ] Scenario 3 produces a 🚨 high-severity Slack message, and reverting restores normal worker operation
- [ ] A manual digest Lambda invocation posts a correctly formatted summary
