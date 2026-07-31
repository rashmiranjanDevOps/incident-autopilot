terraform {
  required_providers {
    archive = { source = "hashicorp/archive" }
  }
}

data "archive_file" "digest" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/digest"
  output_path = "${path.module}/build/digest.zip"
  excludes    = ["test_handler.py", "__pycache__"]
}

resource "aws_cloudwatch_log_group" "digest" {
  name              = "/aws/lambda/${var.name_prefix}-digest"
  retention_in_days = 14
}

resource "aws_iam_role" "digest" {
  name = "${var.name_prefix}-digest"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Read-only against DynamoDB — this function can summarize the audit
# log but can never modify it, enforced here, not just by what the code
# happens to call.
resource "aws_iam_role_policy" "digest" {
  name = "${var.name_prefix}-digest"
  role = aws_iam_role.digest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAuditLogOnly"
        Effect   = "Allow"
        Action   = ["dynamodb:Scan"]
        Resource = var.audit_table_arn
      },
      {
        Sid      = "ReadSlackWebhook"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.slack_secret_arn
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.digest.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "digest" {
  function_name = "${var.name_prefix}-digest"
  role          = aws_iam_role.digest.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.digest.output_path
  source_code_hash = data.archive_file.digest.output_base64sha256

  environment {
    variables = {
      AUDIT_TABLE_NAME         = var.audit_table_name
      SLACK_WEBHOOK_SECRET_ARN = var.slack_secret_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.digest]
}

resource "aws_cloudwatch_event_rule" "weekly_digest" {
  name                = "${var.name_prefix}-weekly-digest"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "weekly_digest" {
  rule = aws_cloudwatch_event_rule.weekly_digest.name
  arn  = aws_lambda_function.digest.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.digest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_digest.arn
}
