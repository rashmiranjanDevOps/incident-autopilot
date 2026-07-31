terraform {
  required_providers {
    archive = { source = "hashicorp/archive" }
  }
}

data "archive_file" "triage" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/triage"
  output_path = "${path.module}/build/triage.zip"
  excludes    = ["test_handler.py", "__pycache__"]
}

resource "aws_cloudwatch_log_group" "triage" {
  name              = "/aws/lambda/${var.name_prefix}-triage"
  retention_in_days = 14
}

resource "aws_iam_role" "triage" {
  name = "${var.name_prefix}-triage"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Triage is the only function in this project with DynamoDB write access
# — centralizing the audit write here (rather than letting Remediate
# also write) keeps the "who can write the audit log" answer to exactly
# one function.
resource "aws_iam_role_policy" "triage" {
  name = "${var.name_prefix}-triage"
  role = aws_iam_role.triage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteAuditLog"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.audit_table_arn
      },
      {
        Sid      = "InvokeRemediateOnly"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = var.remediate_function_arn
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
        Resource = "${aws_cloudwatch_log_group.triage.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "triage" {
  function_name = "${var.name_prefix}-triage"
  role          = aws_iam_role.triage.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 15

  filename         = data.archive_file.triage.output_path
  source_code_hash = data.archive_file.triage.output_base64sha256

  environment {
    variables = {
      AUDIT_TABLE_NAME         = var.audit_table_name
      REMEDIATE_FUNCTION_NAME  = var.remediate_function_name
      SLACK_WEBHOOK_SECRET_ARN = var.slack_secret_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.triage]
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triage.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}

resource "aws_sns_topic_subscription" "triage" {
  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.triage.arn
}
