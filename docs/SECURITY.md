# Security

## Each function only has the permissions it needs

| Role | Can do | Cannot do |
|---|---|---|
| Worker | Receive/delete messages from the work queue only; write its own logs | Touch DynamoDB, invoke any Lambda, touch any other queue |
| Remediate | Get/set reserved concurrency on the worker Lambda **only**; write its own logs | Delete anything, touch DynamoDB, touch any queue, touch any function other than the worker |
| Triage | Write to the audit table; invoke the Remediate Lambda **only**; read the Slack secret; write its own logs | Delete anything, modify any Lambda's configuration directly, read any secret other than the Slack webhook |
| Digest | Read (scan) the audit table only; read the Slack secret; write its own logs | Write to DynamoDB, touch anything else |

None of these roles have a wildcard (`*`) resource on anything that changes state. Every `Resource` is either a specific ARN or scoped to `incident-autopilot-*`.

## Two ways the auto-remediation stays safe

There are really two things stopping the Remediate Lambda from doing something bad:

1. The code itself only knows how to do one thing — raise the worker's concurrency by a small amount. Anything else gets refused.
2. Even if that code had a bug, its IAM role physically can't do anything except adjust the worker's concurrency. No delete permissions, no access to any other resource.

So it's not just "the code is careful" — even if the code were wrong, AWS itself would still block anything outside that one narrow action.

## Secrets

- The Slack webhook lives in Secrets Manager, not in a Terraform variable, an environment default, or version control
- Terraform creates the empty secret; the actual value gets set once, by hand, after the first apply (see `DEPLOYMENT.md`) — so it never ends up in `.tfstate` either
- No Lambda can read any secret except the one it actually needs

## Why the deploy role has more permissions than any single Lambda

The role GitHub Actions uses to deploy this project is more powerful than any one Lambda's runtime role, because it has to be able to *create* those narrower roles in the first place. It's still scoped to this project's resources though — nothing is `iam:*` on `*`. Worth being able to explain this if asked, since at first glance it can look like it contradicts "least privilege," but it doesn't — it's just a different role doing a different job.

## Basic input handling

- The worker Lambda checks that each message body is valid JSON before doing anything with it, and fails loudly instead of silently swallowing bad input
- The Remediate Lambda only runs the one action it's coded to run — anything else gets refused
- If posting to Slack fails, it doesn't crash the pipeline or stop the DynamoDB write — the audit log is the real record, Slack is just a notification on top of it

## What this project isn't

This is a portfolio project, not something that's gone through a real security review. It doesn't cover things like VPC isolation, WAF, GuardDuty, or a formal threat model — that's out of scope for what I was trying to learn here, and I'd rather be upfront about that than pretend otherwise.
