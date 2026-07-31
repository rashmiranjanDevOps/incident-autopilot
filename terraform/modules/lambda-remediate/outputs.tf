output "function_name" { value = aws_lambda_function.remediate.function_name }
output "function_arn"  { value = aws_lambda_function.remediate.arn }
output "role_arn"      { value = aws_iam_role.remediate.arn }
