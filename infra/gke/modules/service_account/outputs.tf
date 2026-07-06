output "email" {
  value = google_service_account.this.email
}

output "annotation" {
  description = "Value for the KSA's iam.gke.io/gcp-service-account annotation"
  value       = google_service_account.this.email
}
