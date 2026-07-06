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

# Canvas security.yml keys (ENCRYPTION_KEY 128, JWT_ENCRYPTION_KEY 64).
resource "random_password" "encryption_key" {
  length  = 128
  special = false
}

resource "random_password" "jwt_encryption_key" {
  length  = 64
  special = false
}

module "cloudsql" {
  source              = "../../modules/cloudsql"
  name                = local.name
  region              = var.region
  network_id          = module.network.network_id
  database_version    = "POSTGRES_17" # prod runs 18.x; 17 is Cloud SQL's max
  tier                = var.db_tier
  db_name             = var.db_name
  db_user             = var.db_user
  db_password         = random_password.db.result
  deletion_protection = var.deletion_protection

  depends_on = [module.network]
}

module "memorystore" {
  source       = "../../modules/memorystore"
  name         = local.name
  region       = var.region
  network_id   = module.network.network_id
  auth_enabled = false # match Canvas cloud66 redis.yml (plain redis://)

  depends_on = [module.network]
}

# ------------------------------------------------------------------------------
# Image registry
# (No object storage — Canvas uses local file storage on a Persistent Disk;
#  see the canvas-files PVC in k8s-manifests-staging.)
# ------------------------------------------------------------------------------
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

  # WI bindings need the cluster's identity pool (PROJECT.svc.id.goog) to exist.
  depends_on = [module.gke]
}

module "external_secrets_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "canvas-external-secrets"
  display_name  = "External Secrets Operator (Canvas)"
  ksa_namespace = "external-secrets"
  ksa_name      = "external-secrets"

  depends_on = [module.gke]
}

module "cert_manager_sa" {
  source        = "../../modules/service_account"
  project_id    = var.project_id
  account_id    = "canvas-cert-manager"
  display_name  = "cert-manager DNS01 solver (Canvas)"
  project_roles = ["roles/dns.admin"]
  ksa_namespace = "cert-manager"
  ksa_name      = "cert-manager"

  depends_on = [module.gke]
}

# ------------------------------------------------------------------------------
# Application secret (assembled from managed infra; read by External Secrets).
# Keys match the env vars Canvas' cloud66 config templates expect. Non-secret
# values (DB name/user/port, domain, admin email) live in the ConfigMap.
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
    # database.yml.cloud66
    POSTGRESQL_ADDRESS  = module.cloudsql.private_ip
    POSTGRESQL_PASSWORD = random_password.db.result
    # redis.yml.cloud66 (AUTH disabled -> host only)
    REDIS_ADDRESS = module.memorystore.host
    # security.yml.cloud66
    ENCRYPTION_KEY     = random_password.encryption_key.result
    JWT_ENCRYPTION_KEY = random_password.jwt_encryption_key.result
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
