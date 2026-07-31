output "queue_url"  { value = aws_sqs_queue.work_queue.id }
output "queue_arn"  { value = aws_sqs_queue.work_queue.arn }
output "queue_name" { value = aws_sqs_queue.work_queue.name }
output "dlq_url"    { value = aws_sqs_queue.dlq.id }
output "dlq_arn"    { value = aws_sqs_queue.dlq.arn }
output "dlq_name"   { value = aws_sqs_queue.dlq.name }

output "table_name" { value = aws_dynamodb_table.audit_log.name }
output "table_arn"  { value = aws_dynamodb_table.audit_log.arn }

output "topic_arn"  { value = aws_sns_topic.alarms.arn }
output "topic_name" { value = aws_sns_topic.alarms.name }

output "secret_arn"  { value = aws_secretsmanager_secret.slack_webhook.arn }
output "secret_name" { value = aws_secretsmanager_secret.slack_webhook.name }
