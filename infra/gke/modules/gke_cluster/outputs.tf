output "name" {
  value = google_container_cluster.this.name
}

output "endpoint" {
  value     = google_container_cluster.this.endpoint
  sensitive = true
}

output "ca_certificate" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}

# projectID.svc.id.goog — the workload identity pool for KSA->GSA bindings.
output "workload_identity_pool" {
  value = "${google_container_cluster.this.name}.svc.id.goog"
}
