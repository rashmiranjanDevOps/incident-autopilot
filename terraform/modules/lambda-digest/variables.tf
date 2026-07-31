variable "name_prefix"      { type = string }
variable "audit_table_arn"  { type = string }
variable "audit_table_name" { type = string }
variable "slack_secret_arn" { type = string }

variable "schedule_expression" {
  description = "EventBridge schedule expression for the digest"
  type        = string
  default     = "rate(7 days)"
}
