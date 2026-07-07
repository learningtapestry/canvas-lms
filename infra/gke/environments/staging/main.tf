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

# Rails secret_key_base — signs the session cookie. Cloud66 auto-injects this;
# on GKE we must provide it, or Canvas can't set the session cookie (login
# breaks). Stable value so sessions survive pod restarts.
resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

module "cloudsql" {
  source              = "../../modules/cloudsql"
  name                = local.name
  region              = var.region
  network_id          = module.network.network_id
  database_version    = "POSTGRES_18" # match prod (18.4) for a clean dump/restore
  zone                = var.db_zone   # co-locate with pods + file PD
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

# GKE Autopilot nodes run as the default compute SA, which has no roles by
# default in new projects — grant it pull access so pods can pull the image.
data "google_project" "this" {
  project_id = var.project_id
}

resource "google_artifact_registry_repository_iam_member" "node_pull" {
  project    = var.project_id
  location   = var.region
  repository = "canvas"
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${data.google_project.this.number}-compute@developer.gserviceaccount.com"

  depends_on = [module.artifact_registry]
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
    # security.yml.cloud66 — reuse the source keys for migrated data (via
    # TF_VAR_*), otherwise a freshly generated key. See variables.tf.
    ENCRYPTION_KEY     = coalesce(var.encryption_key, random_password.encryption_key.result)
    JWT_ENCRYPTION_KEY = coalesce(var.jwt_encryption_key, random_password.jwt_encryption_key.result)
    # Rails cookie signing (Cloud66 auto-provides this; we must too)
    SECRET_KEY_BASE = coalesce(var.secret_key_base, random_password.secret_key_base.result)
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
