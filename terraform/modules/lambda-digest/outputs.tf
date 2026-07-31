output "function_name" { value = aws_lambda_function.digest.function_name }
output "function_arn"  { value = aws_lambda_function.digest.arn }
output "role_arn"      { value = aws_iam_role.digest.arn }
