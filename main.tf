provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

module "terraform_cloud" {
  source  = "saidsef/terraform-cloud-oidc/gcp"
  version = "~> 1.2.0"

  project_id          = var.project_id
  pool_id             = "terraform-cloud"
  organisation        = "yumenomatayume"
  projects            = [{ "project" : "gcp", "workspace" : "gcp" }]
  attribute_condition = "assertion.sub.startsWith('organization:yumenomatayume')"
}


#
# Compute
#

data "google_compute_zones" "available" {
  region = var.region
  status = "UP"
}

data "google_compute_image" "ubuntu" {
  name    = "ubuntu-minimal-2604-resolute-amd64-v20260723"
  project = "ubuntu-os-cloud"
}

resource "google_compute_project_metadata" "ubuntu" {
  metadata = {
    ssh-keys = <<-EOT
      ubuntu:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDurwFQUS2PWIFyWExXL8WiR8PcELCiuB+6ZT4Cgv3rTokBdFoUUt+FuKuETGBBvlhG85teU8b2RyQyzd9nX0LsZ2oPZE0oB1qJkrljwE0QxXj9lNMUqLIGs9pTbPhguFQmlnx+mJ4fMacZc9DDu2uBWOwYGvHgdBf8fbZCDSSHNHC5XKoaSzRZwPGUMr1f7DKinWSQKb9s2Dkasw4GkxAieYL5sbE1/KIb/7nzxv0w6aqwER9SFqqj10otnn5ZVeCu7zpyoITMKAi4126gRKjqVDKai/9zokrCXKCIevSSf3dlQmpvlQXhT7x584zy1ucy83A+ziAYaZOP3v+8m0v9 ubuntu
    EOT
  }
}

resource "google_compute_address" "default" {
  name         = "regional-ip"
  region       = var.region
  address_type = "EXTERNAL"
}

resource "google_compute_instance" "bastion-01" {
  name         = "bastion-01"
  machine_type = "e2-micro"
  zone         = data.google_compute_zones.available.names[0]

  tags = ["terraform"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
      size  = "30"
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.default.address
    }
  }

  service_account {
    scopes = ["userinfo-email", "compute-ro", "storage-ro"]
  }
}


#
# Storage
#

resource "google_storage_bucket" "yumenomatayume" {
  name          = "yumenomatayume"
  location      = "US-CENTRAL1"
  force_destroy = false
  storage_class = "STANDARD"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
}

