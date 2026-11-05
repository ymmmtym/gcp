#
# Discogs backup (Cloud Run + Cloud Scheduler)
#
# アプリ: https://github.com/ymmmtym/discogs-backup
# イメージは GitHub Actions が GHCR に push する（public パッケージ前提）。
# Secret の値は Terraform では持たず、gcloud secrets versions add で投入する。

locals {
  discogs_backup_bucket = google_storage_bucket.yumenomatayume.name
  discogs_backup_prefix = "discogs-backup"

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
