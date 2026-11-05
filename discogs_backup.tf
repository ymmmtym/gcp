#
# Discogs backup (Cloud Run + Cloud Scheduler)
#
# アプリ: https://github.com/ymmmtym/discogs-backup
# イメージは GitHub Actions が GHCR に push する（public パッケージ前提）。
# Secret の値は Terraform では持たず、gcloud secrets versions add で投入する。

locals {
  discogs_backup_service = "discogs-backup"
  discogs_backup_bucket  = google_storage_bucket.yumenomatayume.name
  discogs_backup_prefix  = "discogs-backup"
  discogs_backup_image   = "ghcr.io/ymmmtym/discogs-backup:latest"

  discogs_backup_services = [
    "cloudscheduler.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

resource "google_project_service" "discogs_backup" {
  for_each = toset(local.discogs_backup_services)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------- secrets
resource "google_secret_manager_secret" "discogs_backup_token" {
  secret_id = "discogs-personal-access-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.discogs_backup]
}

resource "google_secret_manager_secret" "discogs_backup_username" {
  secret_id = "discogs-username"

  replication {
    auto {}
  }

  depends_on = [google_project_service.discogs_backup]
}

# ---------------------------------------------------------------- service accounts
resource "google_service_account" "discogs_backup_runtime" {
  account_id   = "discogs-backup-run"
  display_name = "Discogs backup runtime"
}

resource "google_service_account" "discogs_backup_scheduler" {
  account_id   = "discogs-backup-sched"
  display_name = "Discogs backup scheduler"
}

resource "google_storage_bucket_iam_member" "discogs_backup_runtime" {
  bucket = local.discogs_backup_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.discogs_backup_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "discogs_backup_runtime_token" {
  secret_id = google_secret_manager_secret.discogs_backup_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.discogs_backup_runtime.email}"
}

resource "google_secret_manager_secret_iam_member" "discogs_backup_runtime_username" {
  secret_id = google_secret_manager_secret.discogs_backup_username.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.discogs_backup_runtime.email}"
}

# ---------------------------------------------------------------- Cloud Run
resource "google_cloud_run_v2_service" "discogs_backup" {
  name     = local.discogs_backup_service
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.discogs_backup_runtime.email
    timeout         = "600s"

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = local.discogs_backup_image

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      env {
        name  = "BACKUP_FORMAT"
        value = "csv"
      }
      env {
        name  = "BACKUP_DEST"
        value = "gs://${local.discogs_backup_bucket}/${local.discogs_backup_prefix}"
      }
      env {
        name  = "BACKUP_TZ"
        value = "Asia/Tokyo"
      }
      env {
        name = "DISCOGS_USERNAME"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.discogs_backup_username.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "DISCOGS_PERSONAL_ACCESS_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.discogs_backup_token.secret_id
            version = "latest"
          }
        }
      }

      ports {
        container_port = 8080
      }
    }
  }

  # イメージは CI（GHCR）で更新するため、Terraform では差分として扱わない。
  # 更新は `gcloud run services update discogs-backup --image ...` で行う。
  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  depends_on = [
    google_project_service.discogs_backup,
    google_storage_bucket_iam_member.discogs_backup_runtime,
    google_secret_manager_secret_iam_member.discogs_backup_runtime_token,
    google_secret_manager_secret_iam_member.discogs_backup_runtime_username,
  ]
}

# ---------------------------------------------------------------- scheduler
resource "google_cloud_run_v2_service_iam_member" "discogs_backup_scheduler_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.discogs_backup.location
  name     = google_cloud_run_v2_service.discogs_backup.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.discogs_backup_scheduler.email}"
}

resource "google_cloud_scheduler_job" "discogs_backup_daily" {
  name      = "${local.discogs_backup_service}-daily"
  region    = var.region
  schedule  = "0 3 * * *"
  time_zone = "Asia/Tokyo"

  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.discogs_backup.uri}/run"

    oidc_token {
      service_account_email = google_service_account.discogs_backup_scheduler.email
      audience              = google_cloud_run_v2_service.discogs_backup.uri
    }
  }

  # 取得に約 60 秒かかるため、既定の 180 秒から延長する
  attempt_deadline = "600s"

  retry_config {
    retry_count = 1
  }

  depends_on = [google_cloud_run_v2_service_iam_member.discogs_backup_scheduler_invoker]
}

output "discogs_backup_bucket_uri" {
  description = "バックアップ保存先"
  value       = "gs://${local.discogs_backup_bucket}/${local.discogs_backup_prefix}"
}

output "discogs_backup_secrets" {
  description = "Secret Manager の secret ID"
  value = {
    token    = google_secret_manager_secret.discogs_backup_token.secret_id
    username = google_secret_manager_secret.discogs_backup_username.secret_id
  }
}

output "discogs_backup_service_url" {
  description = "Cloud Run サービスの URL"
  value       = google_cloud_run_v2_service.discogs_backup.uri
}

output "discogs_backup_scheduler_job" {
  description = "Cloud Scheduler ジョブ名"
  value       = google_cloud_scheduler_job.discogs_backup_daily.name
}
