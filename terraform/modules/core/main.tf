# Core module — the small, logic-free AWS resources this project needs:
# the work queue, the audit table, the alarm topic, and the Slack secret.
# None of these have any application logic of their own (that's all in
# the lambda-* modules), so they live together in one module instead of
# four separate ones.

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-work-queue-dlq"
  message_retention_seconds = 1209600 # 14 days — long enough to inspect and manually redrive
}

resource "aws_sqs_queue" "work_queue" {
  name                       = "${var.name_prefix}-work-queue"
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount      = var.max_receive_count
  })
}

# One table: every alarm this pipeline sees, the decision made, and the
# outcome.
resource "aws_dynamodb_table" "audit_log" {
  name         = "${var.name_prefix}-audit-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "alarm_name"
  range_key    = "timestamp"

  attribute {
    name = "alarm_name"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }
}

# Every CloudWatch alarm in this project publishes here.
resource "aws_sns_topic" "alarms" {
  name = "${var.name_prefix}-alarms"
}

# Holds the Slack webhook URL. Terraform only creates the empty secret —
# the value is set by hand after the first apply (see docs/DEPLOYMENT.md),
# so a real webhook URL never ends up in a .tf file or in state as a
# plain variable.
resource "aws_secretsmanager_secret" "slack_webhook" {
  name        = "${var.name_prefix}-slack-webhook"
  description = "Slack incoming webhook URL used by the Triage and Digest Lambdas"
}
