# CI access for the Skooner workflows (whitelist + token generation).
#
# The Skooner workflows run `kubectl` against canvas-gke, but the cluster's API
# server is locked to master-authorized-networks (operator IP only), so
# GitHub-hosted runners cannot reach it directly. This wires up GKE Connect
# Gateway: the runner authenticates as an IAM identity through Google's proxy
# instead of needing a whitelisted IP, keeping the API endpoint private.
#
# Reuses the existing Workload Identity Federation pool/provider from
# github-actions.tf; adds a dedicated, powerful service account (kept separate
# from the least-privilege image-builder SA) that the workflows impersonate.

# APIs required for Connect Gateway.
resource "google_project_service" "gkehub" {
  service            = "gkehub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "connectgateway" {
  service            = "connectgateway.googleapis.com"
  disable_on_destroy = false
}

# Register canvas-gke to the project fleet so Connect Gateway can reach it.
resource "google_gke_hub_membership" "canvas" {
  membership_id = var.cluster_name

  endpoint {
    gke_cluster {
      resource_link = "//container.googleapis.com/projects/${var.project_id}/locations/${var.region}/clusters/${var.cluster_name}"
    }
  }

  depends_on = [google_project_service.gkehub]
}

# Dedicated CI identity for Skooner cluster operations. Separate from the
# image-builder SA because the token workflow needs cluster-admin (see below).
resource "google_service_account" "skooner_ci" {
  account_id   = "github-actions-skooner"
  display_name = "GitHub Actions - Skooner cluster ops"
}

# container.admin maps to cluster-admin RBAC in-cluster. Required because the
# token workflow creates ClusterRoleBindings and mints skooner-sa tokens (up to
# cluster-admin). Scope is a single dedicated SA, only usable by this repo's
# workflows via WIF + manual workflow_dispatch. Mirrors the EKS OIDC role.
resource "google_project_iam_member" "skooner_ci_container_admin" {
  project = var.project_id
  role    = "roles/container.admin"
  member  = "serviceAccount:${google_service_account.skooner_ci.email}"
}

# Allows the SA to reach the cluster through Connect Gateway.
resource "google_project_iam_member" "skooner_ci_gateway" {
  project = var.project_id
  role    = "roles/gkehub.gatewayEditor"
  member  = "serviceAccount:${google_service_account.skooner_ci.email}"

  depends_on = [google_project_service.connectgateway]
}

# gkehub.viewer lets get-gke-credentials resolve the membership for the gateway.
resource "google_project_iam_member" "skooner_ci_gkehub_viewer" {
  project = var.project_id
  role    = "roles/gkehub.viewer"
  member  = "serviceAccount:${google_service_account.skooner_ci.email}"
}

# Only this repo's workflows may impersonate the Skooner CI SA (reuses the
# existing WIF pool defined in github-actions.tf).
resource "google_service_account_iam_member" "skooner_ci_wif" {
  service_account_id = google_service_account.skooner_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

output "skooner_ci_service_account" {
  description = "Set as the Skooner workflows' service_account input"
  value       = google_service_account.skooner_ci.email
}
