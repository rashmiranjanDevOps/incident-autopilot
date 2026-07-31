# Final QA report — v1.0 release candidate

Full repository verification pass before treating this as done. Scope: every
`.tf` file, every Lambda handler and test, the CI/CD workflow, every script,
and every doc, checked for internal consistency — not redesigned, not
refactored, not made to look more senior. Only real bugs were touched.

## Method

- Read every file in the repo end to end.
- Cross-checked every Terraform module call in `terraform/main.tf` against
  each module's `variables.tf` (are all required variables actually passed?
  are there unused ones?) and each module's `outputs.tf` (does anything
  reference an output that doesn't exist?).
- Cross-checked every `module.X.Y` reference in `terraform/outputs.tf`
  against the modules actually declared in `terraform/main.tf`.
- Compiled every Lambda file with `python3 -m py_compile` (10/10 passed).
- Ran all four test suites with `pytest` (`worker`, `remediate`, `triage`,
  `digest` — 6 + 7 + 8 + 4 = 25 tests, all passing, matching the count
  `README.md` and `docs/TESTING.md` claim).
- Grepped the whole repo for any remaining reference to the two stale names
  found below, to confirm the fix was complete.
- Checked every doc-to-doc and doc-to-script link in `README.md` and
  `docs/*.md` against the actual filesystem.
- Note: `terraform` itself isn't installed in this environment and the
  provider registry isn't reachable from here, so `terraform validate` /
  `plan` couldn't be run directly. Verification was done by manually
  tracing every module/variable/output reference instead — see above.

## Bugs found and fixed

### 1. `terraform/outputs.tf` — referenced four modules that don't exist

**File:** `terraform/outputs.tf`

**What was wrong:** four outputs referenced `module.secrets`,
`module.dynamodb`, `module.sns`, and `module.sqs`. None of those modules
exist in `terraform/main.tf` — the only modules declared there are
`core`, `lambda_worker`, `lambda_triage`, `lambda_remediate`,
`lambda_digest`, and `alarms`. The SQS queue, DynamoDB table, SNS topic,
and Secrets Manager secret all live inside the single `core` module (see
`terraform/modules/core/main.tf`), not in four separate ones.

**Why it happened:** this reads like a leftover from an earlier draft of
the module layout, before the queue/table/topic/secret were consolidated
into one `core` module. The outputs were never updated to match.

**Impact if left in:** `terraform validate` and `terraform plan` would
both fail immediately with "Reference to undeclared module" — this would
have blocked every future `terraform apply`, including the very first one.

**Fix:** repointed all four outputs at `module.core`, using the output
names that module actually exposes (`secret_name`, `table_name`,
`topic_arn`, `queue_url`, `dlq_url` — confirmed against
`terraform/modules/core/outputs.tf`).

### 2. `lambda/worker/handler.py` — stale docstring reference

**File:** `lambda/worker/handler.py`

**What was wrong:** the `handler()` docstring pointed to
`terraform/modules/sqs` for the DLQ redrive policy. That path doesn't
exist — the redrive policy is defined in `terraform/modules/core/main.tf`.

**Why it happened:** same root cause as bug #1 — a leftover reference to
the pre-consolidation module layout that didn't get updated everywhere.

**Impact if left in:** no functional impact (it's a comment, not code
Terraform or Python actually evaluates), but it would send anyone reading
the code — including an interviewer — to a path that doesn't exist, which
undermines confidence in the rest of the comments.

**Fix:** updated the docstring to point at `terraform/modules/core`.

## What was checked and found correct (no changes made)

- Every other module's `variables.tf` matches exactly what's passed to it
  in `terraform/main.tf` — no missing, extra, or misnamed arguments, for
  `lambda-worker`, `lambda-triage`, `lambda-remediate`, `lambda-digest`,
  and `alarms`.
- Every module's own `outputs.tf` matches what callers actually reference
  (e.g. `module.lambda_worker.function_arn`, `module.core.queue_arn`, etc.
  in `terraform/main.tf` and across sibling modules).
- All `archive_file` `source_dir` paths in the four `lambda-*` modules
  (`${path.root}/../lambda/<function>`) correctly resolve to the real
  `lambda/<function>/` directories given `terraform/` is `path.root`.
- All four Lambda handlers use `handler.handler` as their entry point in
  Terraform, matching the actual function name (`def handler(event,
  context)`) in each `handler.py`.
- All `import` statements in the Lambda code and tests resolve — `from
  handler import ...`, `from slack_notify import post_to_slack`, etc. —
  confirmed by running the actual test suites, not just reading them.
- `docs/DEPLOYMENT.md`, `docs/SECURITY.md`, `docs/TESTING.md`,
  `docs/RUNBOOK.md`, and `docs/ARCHITECTURE.md` all reference real paths
  (`terraform/modules/core/variables.tf`, `terraform/variables.tf`,
  `lambda/triage/rules.json`, etc.) — none pointed at anything stale.
- All `README.md` and `docs/*.md` internal links resolve to real files.
- All six `scripts/*.sh` reference real resource name prefixes, real
  queue/table/function names, and call each other correctly (e.g.
  `cleanup.sh` calling the same policy name `simulate-permission-
  failure.sh` creates).
- The CI/CD workflow (`.github/workflows/ci-cd.yml`) references real
  working directories (`lambda/${{ matrix.function }}`) and real Terraform
  commands in the right order (fmt check → init → validate → plan →
  conditional apply).
- No wildcard (`Resource = "*"`) IAM permissions on anything that changes
  state — every Lambda role is scoped to exactly what it needs.

## Files modified

1. `terraform/outputs.tf` — fixed four broken module references
2. `lambda/worker/handler.py` — fixed one stale docstring path

No other files were touched. No new resources, features, or architectural
changes were introduced.

## Validation performed after the fix

- Re-grepped the repo for `module.secrets`, `module.dynamodb`,
  `module.sns`, `module.sqs`, and the three corresponding stale doc paths
  — zero matches remaining.
- Re-read `terraform/outputs.tf` in full to confirm every `module.X.Y`
  reference now points at a module declared in `terraform/main.tf` and an
  output that module actually exposes.
- Re-compiled every Lambda file with `python3 -m py_compile` — all 10
  pass.
- Re-ran all four test suites — 25/25 tests still pass after the change
  (the fix touched a docstring and a `.tf` file, neither of which the test
  suites exercise, so this was a regression check, not a new pass/fail).

## Final check

**1. Is the repository internally consistent?**
YES — every Terraform module reference, variable, and output now points
at something that actually exists; every doc/script/code cross-reference
was checked and resolves correctly.

**2. Would Terraform fail because of broken references?**
NO, not anymore. Before this pass, `terraform validate` would have failed
on `terraform/outputs.tf`'s four undeclared-module references. That's
fixed. (Caveat: this was verified by manual reference-tracing, since
`terraform` and the provider registry aren't reachable in this
environment — running `terraform init && terraform validate` yourself
before the first real deploy is still worth doing as a final check, but
there's nothing left in the code that should cause it to fail.)

**3. Would you confidently hand this repository to a hiring manager?**
YES. The architecture, IAM scoping, test coverage, and documentation were
already solid going into this pass — the two bugs found were both
cosmetic/reference issues from an earlier draft, not design or logic
flaws, and both are now fixed.
