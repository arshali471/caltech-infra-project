output "plugin_arn"    { value = data.aws_mskconnect_custom_plugin.this.arn }
output "connector_arn" { value = aws_mskconnect_connector.this.arn }
