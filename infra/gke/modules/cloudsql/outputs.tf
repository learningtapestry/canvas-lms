output "instance_name" {
  value = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "For the Cloud SQL Auth Proxy (PROJECT:REGION:INSTANCE)"
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip" {
  description = "Private IP for direct connections (database.yml host)"
  value       = google_sql_database_instance.this.private_ip_address
}
