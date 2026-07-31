output "worker_throttling_alarm_name" { value = aws_cloudwatch_metric_alarm.worker_throttling.alarm_name }
output "dlq_depth_alarm_name"         { value = aws_cloudwatch_metric_alarm.dlq_depth.alarm_name }
output "permission_failure_alarm_name" { value = aws_cloudwatch_metric_alarm.permission_failure.alarm_name }
