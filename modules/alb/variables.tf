###############################################################################
# modules/alb/variables.tf
###############################################################################

variable "name" {
  description = "Name prefix for ALB resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "deletion_protection" {
  description = "Enable deletion protection on the ALB"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener (empty string = HTTP only)"
  type        = string
  default     = ""
}

variable "idle_timeout" {
  description = "Idle timeout (seconds) for ALB connections. 120s handles long-running API calls and streaming."
  type        = number
  default     = 120
}

variable "access_logs_enabled" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = true
}

# ---- Listener & TLS ---------------------------------------------------------

variable "ssl_policy" {
  description = "ALB HTTPS listener SSL policy (cipher suites + protocol versions)"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

# ---- Target Group -----------------------------------------------------------

variable "target_group_port" {
  description = "Port the target group forwards traffic to (EKS ingress node port)"
  type        = number
  default     = 80
}

variable "target_group_protocol" {
  description = "Protocol for the target group (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
}

variable "deregistration_delay" {
  description = "Seconds to wait before deregistering a target from the target group"
  type        = number
  default     = 60
}

# ---- Health Check -----------------------------------------------------------

variable "health_check_path" {
  description = "URL path for the target group health check"
  type        = string
  default     = "/healthz"
}

variable "health_check_interval" {
  description = "Seconds between health check requests"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds to wait for a health check response before marking as unhealthy"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes required to mark a target healthy"
  type        = number
  default     = 3
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures required to mark a target unhealthy"
  type        = number
  default     = 3
}

variable "health_check_matcher" {
  description = "HTTP response codes considered healthy (e.g. 200-399)"
  type        = string
  default     = "200-399"
}

# ---- Tags -------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---- WAF --------------------------------------------------------------------

variable "enable_waf" {
  description = "Attach AWS WAFv2 WebACL to the ALB (AWS Managed Rules + rate limiting per IP)"
  type        = bool
  default     = true
}

variable "waf_rate_limit_per_ip" {
  description = "WAFv2 rate-based rule: max requests per 5-minute window per IP (block above this)"
  type        = number
  default     = 10000
}
