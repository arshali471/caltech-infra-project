###############################################################################
# modules/msk_connect — Debezium PostgreSQL CDC connector on MSK Connect
###############################################################################

data "aws_mskconnect_custom_plugin" "debezium" {
  name = var.custom_plugin_name
}

resource "aws_mskconnect_worker_configuration" "debezium" {
  name = "${var.name}-debezium-worker-config"

  properties_file_content = <<-PROPS
    key.converter=${var.key_converter}
    key.converter.schemas.enable=${var.converter_schemas_enabled}
    value.converter=${var.value_converter}
    value.converter.schemas.enable=${var.converter_schemas_enabled}
    offset.storage.topic=${var.name}-offsets
    config.storage.topic=${var.name}-configs
    status.storage.topic=${var.name}-status
    offset.storage.replication.factor=${var.offset_storage_replication_factor}
    config.storage.replication.factor=${var.config_storage_replication_factor}
    status.storage.replication.factor=${var.status_storage_replication_factor}
  PROPS
}

resource "aws_mskconnect_connector" "debezium" {
  name = "${var.name}-debezium-postgres-connector"

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

  connector_configuration = {
    "connector.class"             = var.connector_class
    "tasks.max"                   = tostring(var.tasks_max)
    "database.hostname"           = var.aurora_source_endpoint
    "database.port"               = tostring(var.database_port)
    "database.user"               = var.aurora_source_username
    "database.password"           = var.aurora_source_password
    "database.dbname"             = var.aurora_source_db_name
    "topic.prefix"                = var.topic_prefix
    "plugin.name"                 = var.logical_decoding_plugin_name
    "slot.name"                   = var.replication_slot_name
    "slot.drop.on.stop"           = "false"
    "publication.name"            = var.publication_name
    "publication.autocreate.mode" = var.publication_autocreate_mode
    "snapshot.mode"               = var.snapshot_mode
    "schema.include.list"         = var.schema_include_list
    "table.include.list"          = var.table_include_list
    "heartbeat.interval.ms"       = tostring(var.heartbeat_interval_ms)
    "decimal.handling.mode"       = var.decimal_handling_mode
    "time.precision.mode"         = var.time_precision_mode
    # SMT — ExtractNewRecordState (unwrap envelope)
    "transforms"                            = "unwrap"
    "transforms.unwrap.type"                = "io.debezium.transforms.ExtractNewRecordState"
    "transforms.unwrap.add.headers"         = "op,ts_ms,source.ts_ms,before.external_sourced_id,before.student_id,before.term_id,before.student_enrollment_id,before.section_id"
    "transforms.unwrap.drop.tombstones"     = "false"
    "transforms.unwrap.delete.handling.mode" = "drop"
    "key.converter"                         = var.key_converter
    "key.converter.schemas.enable"          = tostring(var.converter_schemas_enabled)
    "value.converter"                       = var.value_converter
    "value.converter.schemas.enable"        = tostring(var.converter_schemas_enabled)
  }

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
      arn      = data.aws_mskconnect_custom_plugin.debezium.arn
      revision = data.aws_mskconnect_custom_plugin.debezium.latest_revision
    }
  }

  worker_configuration {
    arn      = aws_mskconnect_worker_configuration.debezium.arn
    revision = aws_mskconnect_worker_configuration.debezium.latest_revision
  }

  service_execution_role_arn = var.msk_connect_role_arn

  log_delivery {
    worker_log_delivery {
      s3 {
        enabled = true
        bucket  = var.logs_bucket_name
        prefix  = var.log_delivery_prefix
      }
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-debezium-connector" })
}
