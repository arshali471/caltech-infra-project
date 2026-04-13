###############################################################################
# modules/alb/main.tf
# Creates: Internet-facing ALB with S3 access logs, HTTP→HTTPS redirect,
#          HTTPS listener (if certificate provided), default target group,
#          WAF association placeholder, and S3 log bucket.
###############################################################################

data "aws_elb_service_account" "this" {}

locals {
  common_tags = merge(var.tags, {
    Module    = "alb"
    ManagedBy = "terraform"
  })

  has_ssl = var.ssl_certificate_arn != ""
}

###############################################################################
# S3 Bucket — ALB Access Logs
###############################################################################

resource "aws_s3_bucket" "alb_logs" {
  count         = var.access_logs_enabled ? 1 : 0
  bucket        = "${var.name}-alb-access-logs"
  force_destroy = false

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb-access-logs"
  })
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count                   = var.access_logs_enabled ? 1 : 0
  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow ALB service account to write logs
resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.this.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs[0].arn}/alb-logs/AWSLogs/*"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs[0].arn}/alb-logs/AWSLogs/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.alb_logs[0].arn
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

###############################################################################
# Application Load Balancer
###############################################################################

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection       = var.deletion_protection
  drop_invalid_header_fields       = true
  idle_timeout                     = var.idle_timeout
  enable_cross_zone_load_balancing = true
  desync_mitigation_mode           = "strictest"

  dynamic "access_logs" {
    for_each = var.access_logs_enabled ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].bucket
      prefix  = "alb-logs"
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb"
  })

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

###############################################################################
# Default Target Group (HTTP — EKS Ingress)
###############################################################################

resource "aws_lb_target_group" "default" {
  name        = "${var.name}-default-tg"
  port        = var.target_group_port
  protocol    = var.target_group_protocol
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = var.target_group_protocol
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    matcher             = var.health_check_matcher
  }

  deregistration_delay = var.deregistration_delay

  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-default-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# Listeners
###############################################################################

# HTTP listener — redirect to HTTPS if cert provided, else forward
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.has_ssl ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.has_ssl ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.default.arn
    }
  }

  tags = local.common_tags
}

# HTTPS listener (only created when ssl_certificate_arn is provided)
resource "aws_lb_listener" "https" {
  count = local.has_ssl ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = local.common_tags
}

###############################################################################
# S3 Access Log Lifecycle (auto-expire old logs to control cost)
###############################################################################

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = var.access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-alb-logs"
    status = "Enabled"
    filter { prefix = "alb-logs/" }
    expiration { days = 90 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

###############################################################################
# WAFv2 — AWS Managed Rules + Rate Limiting (Regional, for ALB)
###############################################################################

resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0

  name  = "${var.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # AWS Managed Core Rule Set (OWASP Top-10 mitigations)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed Known Bad Inputs Rule Set
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-waf-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # AWS Managed SQL Injection Rule Set
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-waf-sqli"
      sampled_requests_enabled   = true
    }
  }

  # Rate-based rule — block IPs exceeding the per-5-minute threshold
  rule {
    name     = "RateLimitPerIP"
    priority = 40
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit_per_ip
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-waf-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_lb.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
