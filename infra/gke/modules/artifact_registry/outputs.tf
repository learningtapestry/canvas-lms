output "repository_id" {
  value = google_artifact_registry_repository.this.repository_id
}

output "registry_host" {
  description = "e.g. us-central1-docker.pkg.dev"
  value       = "${google_artifact_registry_repository.this.location}-docker.pkg.dev"
}
