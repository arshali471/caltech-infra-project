###############################################################################
# modules/ec2/outputs.tf
###############################################################################

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IPv4 address of the instance"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public IPv4 address (empty string when not associated)"
  value       = aws_instance.this.public_ip
}

output "security_group_id" {
  description = "ID of the security group created for this instance"
  value       = aws_security_group.this.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to this instance"
  value       = aws_iam_role.this.arn
}

output "iam_role_name" {
  description = "Name of the IAM role attached to this instance"
  value       = aws_iam_role.this.name
}
