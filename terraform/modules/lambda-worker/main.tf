terraform {
  required_providers {
    archive = { source = "hashicorp/archive" }
  }
}

data "archive_file" "worker" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/worker"
  output_path = "${path.module}/build/worker.zip"
  excludes    = ["test_handler.py", "__pycache__"]
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${var.name_prefix}-worker"
  retention_in_days = 14
}

resource "aws_iam_role" "worker" {
  name = "${var.name_prefix}-worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Least privilege: read + delete from the work queue (to consume
# messages), write its own logs. Nothing else — specifically no
# DynamoDB access and no permission to touch any other function or
# queue. This is the role scenario 3's simulate-permission-failure.sh
# temporarily narrows, to prove the pipeline handles a permission error
# it did not cause.
resource "aws_iam_role_policy" "worker" {
  name = "${var.name_prefix}-worker"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ConsumeQueue"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
        ]
        Resource = var.queue_arn
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.worker.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "worker" {
  function_name = "${var.name_prefix}-worker"
  role          = aws_iam_role.worker.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 15

  # Deliberately constrained — this project intentionally demos what
  # happens when it's too low for the current load. See scripts/chaos.sh
  # and the "worker throttling" scenario in docs/RUNBOOK.md. The
  # Remediate Lambda's only allowed action raises this, safely and
  # incrementally, when that happens.
  reserved_concurrent_executions = var.reserved_concurrency

  filename         = data.archive_file.worker.output_path
  source_code_hash = data.archive_file.worker.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.worker]
}

resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn = var.queue_arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 5
}
