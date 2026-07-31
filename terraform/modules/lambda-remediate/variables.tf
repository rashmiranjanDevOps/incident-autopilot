variable "name_prefix" {
  type = string
}

variable "worker_function_arn" {
  description = "The ONLY function this Lambda is permitted to modify"
  type        = string
}

variable "worker_function_name" {
  type = string
}

variable "max_reserved_concurrency" {
  description = "Hard cap — the remediation action never raises the worker past this, however many times it fires"
  type        = number
  default     = 10
}

variable "concurrency_increment" {
  description = "How much to raise reserved concurrency by per remediation"
  type        = number
  default     = 5
}
