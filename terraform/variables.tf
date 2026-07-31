variable "aws_region" {
  description = "AWS region everything is deployed into"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "owner/repo allowed to assume the GitHub Actions deploy role, e.g. \"yourusername/incident-autopilot\""
  type        = string
  default     = "rashmiranjanDevOps/incident-autopilot"
}

variable "project_name" {
  description = "Prefix used for every resource name in the project — keep this in sync with the deploy role's IAM policy above, which is scoped to this prefix"
  type        = string
  default     = "incident-autopilot"
}

variable "worker_reserved_concurrency" {
  description = "Deliberately low — this is what scripts/chaos.sh exceeds to demo scenario 1"
  type        = number
  default     = 2
}

variable "worker_max_reserved_concurrency" {
  description = "Hard cap the Remediate Lambda will never raise the worker past"
  type        = number
  default     = 10
}

variable "worker_concurrency_increment" {
  description = "How much the Remediate Lambda raises reserved concurrency by, per remediation"
  type        = number
  default     = 5
}

variable "digest_schedule_expression" {
  description = "EventBridge schedule expression for the weekly digest"
  type        = string
  default     = "rate(7 days)"
}
