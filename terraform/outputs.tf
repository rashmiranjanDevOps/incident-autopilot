output "aws_account_id" {
  description = "AWS account these resources were deployed into"
  value       = data.aws_caller_identity.current.account_id
}

output "github_actions_role_arn" {
  description = "Add this as the GitHub repo secret AWS_GITHUB_ACTIONS_ROLE_ARN so CI can deploy"
  value       = aws_iam_role.github_actions.arn
}

output "slack_webhook_secret_name" {
  description = "Set this secret's VALUE by hand after the first apply — see docs/DEPLOYMENT.md"
  value       = module.core.secret_name
}

output "audit_table_name" {
  value = module.core.table_name
}

output "sns_topic_arn" {
  value = module.core.topic_arn
}

output "work_queue_url" {
  value = module.core.queue_url
}

output "dlq_url" {
  value = module.core.dlq_url
}

output "worker_function_name" {
  value = module.lambda_worker.function_name
}

