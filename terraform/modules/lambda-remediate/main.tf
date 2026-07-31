terraform {
  required_providers {
    archive = { source = "hashicorp/archive" }
  }
}

data "archive_file" "remediate" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/remediate"
  output_path = "${path.module}/build/remediate.zip"
  excludes    = ["test_handler.py", "__pycache__"]
}

resource "aws_cloudwatch_log_group" "remediate" {
  name              = "/aws/lambda/${var.name_prefix}-remediate"
  retention_in_days = 14
}

resource "aws_iam_role" "remediate" {
  name = "${var.name_prefix}-remediate"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# This is the policy the whole "safe auto-remediation" claim rests on.
# It grants exactly two actions, on exactly ONE function (the worker) —
# nothing that deletes anything, nothing that touches any other
# resource. Adding a new safe action later means adding one more
# narrowly-scoped statement here, in the same commit as the code that
# implements it — see lambda/remediate/handler.py's ALLOWED_ACTIONS.
resource "aws_iam_role_policy" "remediate" {
  name = "${var.name_prefix}-remediate"
  role = aws_iam_role.remediate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AdjustWorkerConcurrencyOnly"
        Effect = "Allow"
        Action = [
          "lambda:GetFunctionConcurrency",
          "lambda:PutFunctionConcurrency",
        ]
        Resource = var.worker_function_arn
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.remediate.arn}:*"
      },
    ]
  })
}

resource "aws_lambda_function" "remediate" {
  function_name = "${var.name_prefix}-remediate"
  role          = aws_iam_role.remediate.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 10

  filename         = data.archive_file.remediate.output_path
  source_code_hash = data.archive_file.remediate.output_base64sha256

  environment {
    variables = {
      WORKER_FUNCTION_NAME      = var.worker_function_name
      MAX_RESERVED_CONCURRENCY  = tostring(var.max_reserved_concurrency)
      CONCURRENCY_INCREMENT     = tostring(var.concurrency_increment)
    }
  }

  depends_on = [aws_cloudwatch_log_group.remediate]
}
