terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Cloud SQL for PostgreSQL with a private IP (no public exposure).
resource "google_sql_database_instance" "this" {
  name                = var.name
  region              = var.region
  database_version    = var.database_version
  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.availability_type # ZONAL for staging, REGIONAL for prod
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size
    disk_autoresize   = true

    # Pin the zone so the DB stays co-located with the pods + file PD
    # (avoids a cross-zone dependency). Only meaningful for ZONAL instances.
    dynamic "location_preference" {
      for_each = var.zone == null ? [] : [1]
      content {
        zone = var.zone
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
    }

    maintenance_window {
      day  = 7 # Sunday
      hour = 4
    }
  }
}

resource "google_sql_database" "db" {
  name     = var.db_name
  instance = google_sql_database_instance.this.name
}

resource "google_sql_user" "user" {
  name     = var.db_user
  instance = google_sql_database_instance.this.name
  password = var.db_password
}
