# terraform/main.tf
#
# Single environment, single state file — this is a demo pipeline, not a
# live service, so a dev/prod split would add complexity without a real
# benefit. See docs/ARCHITECTURE.md for more on how this is put together.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    # Values supplied at init time: terraform init -backend-config=backend.hcl
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "incident-autopilot"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ─── GitHub Actions OIDC ───────────────────────────────────────────────────
# GitHub issues a short-lived token for each workflow run; AWS trusts it
# was really issued by GitHub, then hands out short-lived credentials
# scoped to the role below. No AWS access key is stored as a GitHub secret.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list intentionally omitted — AWS validates GitHub's
  # certificate chain itself now, no manual thumbprint needed.
}

resource "aws_iam_role" "github_actions" {
  name = "incident-autopilot-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRoleWithWebIdentity"
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github_actions.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Scoped to this one repo, so no other GitHub repo can assume this role.
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })
}

# Terraform state access — reading/writing the state file and the lock table.
resource "aws_iam_role_policy" "github_actions_state" {
  name = "incident-autopilot-github-actions-state"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StateBucket"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::incident-autopilot-tfstate-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::incident-autopilot-tfstate-${data.aws_caller_identity.current.account_id}/*",
        ]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/incident-autopilot-tf-locks"
      },
    ]
  })
}

# Permissions to actually manage the project's AWS resources. Everything
# is scoped to "incident-autopilot*" resources, not "*" — except the IAM
# and event-source-mapping actions, which AWS doesn't support scoping
# that tightly. This role ends up more powerful than any single Lambda's
# runtime role, because it has to be able to create those narrower roles
# in the first place — worth being able to explain that if asked.
resource "aws_iam_role_policy" "github_actions_project" {
  name = "incident-autopilot-github-actions-project"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageProjectIamRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole",
          "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:TagRole", "iam:PassRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/incident-autopilot-*"
      },
      {
        Sid      = "ManageQueues"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:incident-autopilot-*"
      },
      {
        Sid      = "ManageAuditTable"
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/incident-autopilot-*"
      },
      {
        Sid      = "ManageAlarmTopic"
        Effect   = "Allow"
        Action   = ["sns:*"]
        Resource = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:incident-autopilot-*"
      },
      {
        Sid      = "ManageLambda"
        Effect   = "Allow"
        Action   = ["lambda:*"]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:incident-autopilot-*"
      },
      {
        Sid    = "ManageEventSourceMappingsGlobal"
        Effect = "Allow"
        Action = [
          "lambda:CreateEventSourceMapping", "lambda:GetEventSourceMapping",
          "lambda:UpdateEventSourceMapping", "lambda:DeleteEventSourceMapping",
          "lambda:ListEventSourceMappings",
        ]
        Resource = "*" # this API family has no resource-level ARN scoping
      },
      {
        Sid      = "ManageSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:*"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:incident-autopilot-*"
      },
      {
        Sid      = "ManageEventBridgeSchedule"
        Effect   = "Allow"
        Action   = ["events:*"]
        Resource = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/incident-autopilot-*"
      },
      {
        Sid    = "ManageLogsAndMetricFilters"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy", "logs:TagResource",
          "logs:PutMetricFilter", "logs:DeleteMetricFilter", "logs:DescribeMetricFilters",
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/incident-autopilot-*"
      },
      {
        Sid      = "ManageAlarms"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms"]
        Resource = "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:incident-autopilot-*"
      },
    ]
  })
}

# ─── The pipeline itself ────────────────────────────────────────────────────
locals {
  name_prefix = var.project_name
}

module "core" {
  source      = "./modules/core"
  name_prefix = local.name_prefix
}

module "lambda_worker" {
  source               = "./modules/lambda-worker"
  name_prefix          = local.name_prefix
  queue_arn            = module.core.queue_arn
  reserved_concurrency = var.worker_reserved_concurrency
}

module "lambda_remediate" {
  source                   = "./modules/lambda-remediate"
  name_prefix              = local.name_prefix
  worker_function_arn      = module.lambda_worker.function_arn
  worker_function_name     = module.lambda_worker.function_name
  max_reserved_concurrency = var.worker_max_reserved_concurrency
  concurrency_increment    = var.worker_concurrency_increment
}

module "lambda_triage" {
  source                  = "./modules/lambda-triage"
  name_prefix             = local.name_prefix
  audit_table_arn         = module.core.table_arn
  audit_table_name        = module.core.table_name
  remediate_function_arn  = module.lambda_remediate.function_arn
  remediate_function_name = module.lambda_remediate.function_name
  slack_secret_arn        = module.core.secret_arn
  sns_topic_arn           = module.core.topic_arn
}

module "lambda_digest" {
  source              = "./modules/lambda-digest"
  name_prefix         = local.name_prefix
  audit_table_arn     = module.core.table_arn
  audit_table_name    = module.core.table_name
  slack_secret_arn    = module.core.secret_arn
  schedule_expression = var.digest_schedule_expression
}

module "alarms" {
  source                = "./modules/alarms"
  name_prefix           = local.name_prefix
  worker_function_name  = module.lambda_worker.function_name
  worker_log_group_name = module.lambda_worker.log_group_name
  dlq_name              = module.core.dlq_name
  sns_topic_arn         = module.core.topic_arn
}
