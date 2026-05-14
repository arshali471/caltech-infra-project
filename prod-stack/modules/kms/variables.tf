variable "name" {
  description = "Resource name prefix (project-environment)"
  type        = string
}

variable "deletion_window_days" {
  description = "KMS key deletion window in days (7-30)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
