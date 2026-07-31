variable "name_prefix" {
  type = string
}

variable "queue_arn" {
  description = "ARN of the SQS work queue this function consumes from"
  type        = string
}

variable "reserved_concurrency" {
  description = "Intentionally low by default — see the comment on aws_lambda_function.worker"
  type        = number
  default     = 2
}
