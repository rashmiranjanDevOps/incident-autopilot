output "function_name"   { value = aws_lambda_function.worker.function_name }
output "function_arn"    { value = aws_lambda_function.worker.arn }
output "role_arn"        { value = aws_iam_role.worker.arn }
output "role_name"       { value = aws_iam_role.worker.name }
output "log_group_name"  { value = aws_cloudwatch_log_group.worker.name }
