output "cluster_name" {
  value = module.gke.name
}

output "registry_host" {
  description = "Artifact Registry host (set in image paths)"
  value       = module.artifact_registry.registry_host
}

output "cloudsql_connection_name" {
  value = module.cloudsql.connection_name
}

output "cloudsql_private_ip" {
  value = module.cloudsql.private_ip
}

output "attachments_bucket" {
  value = module.attachments_bucket.name
}

output "app_service_account_email" {
  description = "Set as the canvas-app KSA iam.gke.io/gcp-service-account annotation"
  value       = module.app_sa.email
}

output "external_secrets_service_account_email" {
  value = module.external_secrets_sa.email
}

output "cert_manager_service_account_email" {
  value = module.cert_manager_sa.email
}

output "app_secret_name" {
  description = "Secret Manager key the ExternalSecret reads"
  value       = google_secret_manager_secret.app.secret_id
}
