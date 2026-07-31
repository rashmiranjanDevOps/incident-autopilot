variable "name_prefix" {
  type = string
}

variable "visibility_timeout_seconds" {
  description = "How long a message is hidden from other consumers after being received"
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "How many times a message can fail before it moves to the DLQ"
  type        = number
  default     = 3
}
