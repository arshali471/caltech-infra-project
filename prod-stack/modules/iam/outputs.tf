output "ec2_instance_profile_name" { value = aws_iam_instance_profile.ec2_app.name }
output "ec2_role_arn"              { value = aws_iam_role.ec2_app.arn }
output "msk_connect_role_arn"      { value = aws_iam_role.msk_connect.arn }
