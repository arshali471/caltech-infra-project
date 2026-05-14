output "instance_id" { value = aws_instance.app.id }
output "public_ip"   { value = aws_instance.app.public_ip }
output "private_ip"  { value = aws_instance.app.private_ip }
