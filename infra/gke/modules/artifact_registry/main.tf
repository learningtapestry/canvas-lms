terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Docker image repository for the Canvas app image.
resource "google_artifact_registry_repository" "this" {
  repository_id = var.repository_id
  location      = var.region
  format        = "DOCKER"
  description   = var.description

  docker_config {
    immutable_tags = var.immutable_tags
  }

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = var.keep_count
    }
  }
}
