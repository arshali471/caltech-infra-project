output "plugin_arn"    { value = aws_mskconnect_custom_plugin.debezium.arn }
output "connector_arn" { value = aws_mskconnect_connector.debezium.arn }
