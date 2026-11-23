#
# GCE 監視（Cloud Monitoring）
#
# Slack 通知チャネルはコンソールで作成済みのものを data source で参照する。
# bot token を Terraform state に持たせないための意図的な線引きで、
# 監視内容（uptime check / alert policy）だけをコード管理する。

resource "google_project_service" "monitoring" {
  project            = var.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

data "google_monitoring_notification_channel" "slack" {
  type = "slack"

  depends_on = [google_project_service.monitoring]
}

# SSH ポートを 1 分間隔で USA の 3 ロケーションから確認する。
# 実行回数は約 13 万/月で、無料枠（100 万/月）に収まる。
resource "google_monitoring_uptime_check_config" "bastion_ssh" {
  display_name = "${google_compute_instance.us-bastion-01.name} ssh"
  timeout      = "10s"
  period       = "60s"

  selected_regions = ["USA"]

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = google_compute_address.default.address
    }
  }

  tcp_check {
    port = 22
  }

  depends_on = [google_project_service.monitoring]
}

resource "google_monitoring_alert_policy" "bastion_uptime" {
  display_name = "${google_compute_instance.us-bastion-01.name} unreachable"
  combiner     = "OR"

  conditions {
    display_name = "uptime check failed"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.bastion_ssh.uptime_check_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "300s"

      trigger {
        count = 1
      }

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }
    }
  }

  notification_channels = [data.google_monitoring_notification_channel.slack.name]
}

resource "google_monitoring_alert_policy" "bastion_cpu" {
  display_name = "${google_compute_instance.us-bastion-01.name} cpu high"
  combiner     = "OR"

  conditions {
    display_name = "cpu utilization > 80% for 10m"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id=\"${google_compute_instance.us-bastion-01.instance_id}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "600s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [data.google_monitoring_notification_channel.slack.name]
}

#
# Cloud Run（discogs-backup）はスケール・トゥ・ゼロの日次バッチなので、
# 死活監視ではなく「実行が失敗したか」をログで監視する。
# 認証必須のサービスに uptime check を当てると 403 で常時発報するため行わない。
resource "google_monitoring_alert_policy" "discogs_backup_errors" {
  display_name = "${google_cloud_run_v2_service.discogs_backup.name} errors"
  combiner     = "OR"

  conditions {
    display_name = "error or 5xx log"

    condition_matched_log {
      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.discogs_backup.name}\" AND (severity>=ERROR OR httpRequest.status>=500)"
    }
  }

  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }

  notification_channels = [data.google_monitoring_notification_channel.slack.name]
}
