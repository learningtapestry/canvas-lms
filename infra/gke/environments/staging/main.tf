locals {
  name            = "canvas-${var.env}"
  namespace       = "canvas-${var.env}"
  ksa_app         = "canvas-app"
  app_secret_name = "canvas-secrets-${var.env}"
}

# ------------------------------------------------------------------------------
# Networking (VPC, subnet, NAT, Private Service Access)
# ------------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"
  name   = local.name
  region = var.region
}

# ------------------------------------------------------------------------------
# GKE Autopilot cluster
# ------------------------------------------------------------------------------
module "gke" {
  source                     = "../../modules/gke_cluster"
  name                       = var.cluster_name
  region                     = var.region
  network_id                 = module.network.network_id
  subnet_id                  = module.network.subnet_id
  pods_range_name            = module.network.pods_range_name
  services_range_name        = module.network.services_range_name
  master_authorized_networks = var.master_authorized_networks
  deletion_protection        = var.deletion_protection
}

# ------------------------------------------------------------------------------
# Data services (Cloud SQL + Memorystore) — depend on PSA being established
# ------------------------------------------------------------------------------
resource "random_password" "db" {
  length  = 32
  special = false
}

# Canvas security.yml encryption_key (must be >= 20 chars).
resource "random_password" "encryption_key" {
  length  = 48
  special = false
}

module "cloudsql" {
  source              = "../../modules/cloudsql"
  name                = local.name
  region              = var.region
  network_id          = module.network.network_id
  tier                = var.db_tier
  db_name             = var.db_name
  db_user             = var.db_user
  db_password         = random_password.db.result
  deletion_protection = var.deletion_protection

  depends_on = [module.network]
}

module "memorystore" {
  source     = "../../modules/memorystore"
  name       = local.name
  region     = var.region
  network_id = module.network.network_id

  depends_on = [module.network]
}

# ------------------------------------------------------------------------------
# Object storage + image registry
# ------------------------------------------------------------------------------
module "attachments_bucket" {
  source = "../../modules/gcs_bucket"
  name   = var.attachments_bucket
}

module "artifact_registry" {
  source        = "../../modules/artifact_registry"
  repository_id = "canvas"
  region        = var.region
}

# ------------------------------------------------------------------------------
# Service accounts + Workload Identity bindings
# ------------------------------------------------------------------------------
module "app_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "canvas-app"
  display_name  = "Canvas app + jobs (${var.env})"
  project_roles = ["roles/cloudsql.client"]
  ksa_namespace = local.namespace
  ksa_name      = local.ksa_app
}

module "external_secrets_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "canvas-external-secrets"
  display_name  = "External Secrets Operator (Canvas)"
  ksa_namespace = "external-secrets"
  ksa_name      = "external-secrets"
}

module "cert_manager_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "canvas-cert-manager"
  display_name  = "cert-manager DNS01 solver (Canvas)"
  project_roles = ["roles/dns.admin"]
  ksa_namespace = "cert-manager"
  ksa_name      = "cert-manager"
}

# Attachment storage: grant the app object access, then mint an HMAC key so
# Canvas' S3 driver can talk to GCS via the S3-interoperability API.
resource "google_storage_bucket_iam_member" "app_attachments" {
  bucket = module.attachments_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.app_sa.email}"
}

resource "google_storage_hmac_key" "app" {
  service_account_email = module.app_sa.email
}

# ------------------------------------------------------------------------------
# Application secret (assembled from managed infra; read by External Secrets)
# ------------------------------------------------------------------------------
resource "google_secret_manager_secret" "app" {
  secret_id = local.app_secret_name
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "app" {
  secret = google_secret_manager_secret.app.id
  secret_data = jsonencode({
    # database.yml
    DB_HOST     = module.cloudsql.private_ip
    DB_NAME     = var.db_name
    DB_USERNAME = var.db_user
    DB_PASSWORD = random_password.db.result
    # security.yml
    ENCRYPTION_KEY = random_password.encryption_key.result
    # redis.yml / cache_store.yml
    REDIS_URL = "redis://:${module.memorystore.auth_string}@${module.memorystore.host}:${module.memorystore.port}/0"
    # amazon_s3.yml (GCS via S3 interop)
    GCS_BUCKET            = module.attachments_bucket.name
    GCS_HMAC_ACCESS_KEY   = google_storage_hmac_key.app.access_id
    GCS_HMAC_SECRET_KEY   = google_storage_hmac_key.app.secret
    GCS_S3_INTEROP_REGION = var.region
  })
}

# Only the app + External Secrets GSAs may read it.
resource "google_secret_manager_secret_iam_member" "app_read" {
  secret_id = google_secret_manager_secret.app.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.app_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_read" {
  secret_id = google_secret_manager_secret.app.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.external_secrets_sa.email}"
}
