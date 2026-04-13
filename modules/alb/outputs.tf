###############################################################################
# modules/alb/outputs.tf
###############################################################################

output "alb_id" {
  description = "ID of the Application Load Balancer"
  value       = aws_lb.this.id
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Route 53 canonical hosted zone ID of the ALB (for alias records)"
  value       = aws_lb.this.zone_id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (null if no SSL cert provided)"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}

output "default_target_group_arn" {
  description = "ARN of the default target group"
  value       = aws_lb_target_group.default.arn
}

output "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs"
  value       = var.access_logs_enabled ? aws_s3_bucket.alb_logs[0].bucket : null
}

output "waf_web_acl_arn" {
  description = "ARN of the WAFv2 WebACL attached to the ALB (null if WAF disabled)"
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
}
