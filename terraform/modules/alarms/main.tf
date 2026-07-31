# Three alarms, one per incident-simulation scenario in docs/RUNBOOK.md.
# Each alarm_name below matches a key in lambda/triage/rules.json exactly
# — that string match is how the Triage Lambda knows which rule applies.

# ─── Scenario 1: worker throttling (auto-remediated) ───────────────────
resource "aws_cloudwatch_metric_alarm" "worker_throttling" {
  alarm_name          = "${var.name_prefix}-worker-throttling"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Worker Lambda is being throttled — reserved concurrency is too low for current load"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.worker_function_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# ─── Scenario 2: DLQ backlog (escalated, never auto-remediated) ────────
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name_prefix}-dlq-depth"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Messages have exhausted retries and landed in the dead-letter queue"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [var.sns_topic_arn]
}

# ─── Scenario 3: permission failure (always escalated) ─────────────────
# CloudWatch Alarms can't watch for a string in logs directly — a metric
# filter turns "AccessDenied appeared in the worker's logs" into a real
# numeric metric, which an alarm CAN watch.
resource "aws_cloudwatch_log_metric_filter" "permission_failure" {
  name           = "${var.name_prefix}-permission-failure"
  log_group_name = var.worker_log_group_name
  pattern        = "AccessDenied"

  metric_transformation {
    name      = "PermissionFailures"
    namespace = "IncidentAutopilot"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "permission_failure" {
  alarm_name          = "${var.name_prefix}-permission-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.permission_failure.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.permission_failure.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Worker Lambda hit an AccessDenied error — never auto-remediated, always escalated"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
}
