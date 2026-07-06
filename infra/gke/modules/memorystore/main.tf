terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# Memorystore for Redis (Canvas cache + inst-jobs locking).
# BASIC tier for staging; use STANDARD_HA (with replicas) for prod.
resource "google_redis_instance" "this" {
  name               = var.name
  region             = var.region
  tier               = var.tier
  memory_size_gb     = var.memory_size_gb
  redis_version      = var.redis_version
  authorized_network = var.network_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  # Canvas' cloud66 redis.yml uses a plain redis:// URL (no auth/TLS), so we
  # match that on a private VPC.
  auth_enabled            = var.auth_enabled
  transit_encryption_mode = var.auth_enabled ? "SERVER_AUTHENTICATION" : "DISABLED"
}
