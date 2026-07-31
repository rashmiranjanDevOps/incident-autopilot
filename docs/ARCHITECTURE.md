# Architecture

This is the deeper explanation of how the pipeline fits together. For the short version with a diagram, see the README.

## Detection side — how an incident gets created and noticed

```
Worker Lambda (simulated background job)
  reads from:  SQS queue "incident-autopilot-work-queue"
  behavior:    a normal message is processed and logged; a message
               with "poison": true always fails, on every attempt
        │
        │ repeated failure -> SQS redrive policy (max 3 attempts)
        v
  SQS dead-letter queue "incident-autopilot-work-queue-dlq"

Separately, if scripts/chaos.sh sends more messages at once than the
worker's reserved concurrency (2) can handle, AWS throttles it directly
— a real capacity problem, not a simulated one.

Both the worker Lambda's Throttles metric AND the DLQ's message count
are watched by CloudWatch Alarms, and a log metric filter turns
"AccessDenied" in the worker's logs into a third watchable metric.
All three alarms publish to one shared SNS topic.
```

## Response side — how the pipeline reacts

```
SNS topic (alarm notifications)
        │
        v
Triage Lambda
  reads:  rules.json (alarm_name -> severity, safe_to_remediate, action)
        │
   ┌────┴─────┐
 safe?      not safe / unrecognized
   │           │
   v           v
Remediate    Slack escalation
Lambda       (severity, alarm, runbook
(whitelisted  link — no auto action)
action only)
   └────┬──────┘
        v
DynamoDB audit log (every alarm, decision, and outcome — timestamped)
        │
        v (separately, on a schedule)
EventBridge (weekly) -> Digest Lambda -> Slack summary
```

## A few decisions worth explaining

**Why I dropped the original "chaos toggle" idea.** My first plan was one on/off switch that made the worker fail randomly. Once I actually nailed down the three scenarios I wanted to demo, none of them needed randomness — each one has a more specific, realistic trigger: throttling happens for real when `scripts/chaos.sh` sends a burst of messages at once, the DLQ scenario uses a message that's coded to always fail (`"poison": true`), and the permission-failure scenario comes from a script that temporarily edits the IAM policy. Three specific triggers turned out to be easier to explain than one random one.

**Why there's no dev/prod split.** This is a demo pipeline, not something serving real traffic, so a second environment would just be extra Terraform complexity for no real benefit.

**Why each Lambda has its own IAM role instead of one shared role.** Worker only needs to read its queue. Remediate only needs to touch the worker's concurrency setting. Triage only needs to write the audit table and call Remediate. Digest only needs to read the audit table. Splitting them means you can answer "what can this function actually do" by reading one small file instead of one big shared policy.

**Why only Triage writes to DynamoDB.** Keeping the write in one place means there's exactly one answer to "what can write the audit log," and it's easy to check.

**Why the GitHub Actions deploy role has more permissions than any single Lambda's role.** It has to be able to create those narrower roles in the first place, so it's necessarily broader than any one of them — but it's still scoped to this project's resources, not `*`. More on this in `SECURITY.md`.

**Why EventBridge is only used for the weekly digest.** CloudWatch Alarms can publish straight to SNS on their own — no extra step needed there. EventBridge is just for turning a weekly schedule into a Lambda call.

**Why a log metric filter for the permission-failure alarm.** CloudWatch Alarms can only watch numbers, not text in logs. A metric filter turns "the string `AccessDenied` showed up in the worker's logs" into an actual number that an alarm can watch — a pretty common AWS trick once you know it exists.

## What each AWS service is doing here

- **SQS + DLQ** — the queue for "work," and a place for messages that fail every retry to land instead of disappearing.
- **Lambda (×4)** — worker, triage, remediate, digest. Kept as four small functions instead of one big one so each can have its own narrow permissions and be tested on its own.
- **CloudWatch (alarms, logs, metric filter)** — the only thing actually watching for problems.
- **SNS** — one topic that every alarm publishes to, which the Triage Lambda listens on.
- **DynamoDB** — one table logging every alarm, what was decided, and what happened.
- **EventBridge** — just the weekly cron trigger for the digest.
- **Secrets Manager** — holds the Slack webhook URL so it's never hardcoded anywhere.
- **IAM** — one narrow role per Lambda, plus a broader (but still scoped) role for deploying.
- **GitHub Actions + OIDC** — CI/CD, using the same pattern as my other project so both repos are consistent.
- **Terraform's archive provider** — zips each Lambda's source at plan time, so there's no separate packaging step that could get out of sync with the code.
