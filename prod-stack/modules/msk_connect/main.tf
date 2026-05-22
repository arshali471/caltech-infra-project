###############################################################################
# modules/msk_connect — Generic MSK Connect connector (source or sink)
# Caller passes the full connector_configuration map and connector_name_suffix.
###############################################################################

data "aws_mskconnect_custom_plugin" "this" {
  name = var.custom_plugin_name
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/mskconnect/${var.name}-${var.connector_name_suffix}"
  retention_in_days = 90
  tags              = var.tags
}

resource "aws_mskconnect_worker_configuration" "this" {
  name = "${var.name}-${var.connector_name_suffix}-worker-config"

  properties_file_content = <<-PROPS
    key.converter=${var.key_converter}
    key.converter.schemas.enable=${var.converter_schemas_enabled}
    value.converter=${var.value_converter}
    value.converter.schemas.enable=${var.converter_schemas_enabled}
    connector.client.config.override.policy=All
  PROPS
}

resource "aws_mskconnect_connector" "this" {
  name = "${var.name}-${var.connector_name_suffix}"

  kafkaconnect_version = var.kafkaconnect_version

  capacity {
    autoscaling {
      mcu_count        = var.mcu_count
      min_worker_count = var.min_workers
      max_worker_count = var.max_workers
      scale_in_policy  { cpu_utilization_percentage = var.scale_in_cpu_pct }
      scale_out_policy { cpu_utilization_percentage = var.scale_out_cpu_pct }
    }
  }

  connector_configuration = var.connector_configuration

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.bootstrap_servers

      vpc {
        security_groups = [var.msk_connect_sg_id]
        subnets         = var.private_subnet_ids
      }
    }
  }

  kafka_cluster_client_authentication { authentication_type = "IAM" }
  kafka_cluster_encryption_in_transit { encryption_type     = "TLS" }

  plugin {
    custom_plugin {
      arn      = data.aws_mskconnect_custom_plugin.this.arn
      revision = data.aws_mskconnect_custom_plugin.this.latest_revision
    }
  }

  worker_configuration {
    arn      = aws_mskconnect_worker_configuration.this.arn
    revision = aws_mskconnect_worker_configuration.this.latest_revision
  }

  service_execution_role_arn = var.msk_connect_role_arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.this.name
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-${var.connector_name_suffix}" })
}
