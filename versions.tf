terraform {
  backend "remote" {
    organization = "yumenomatayume"

    workspaces {
      name = "gcp"
    }
  }

  required_version = "~> 1.16.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}
