output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}

output "pods_range_name" {
  value = "pods"
}

output "services_range_name" {
  value = "services"
}

# Consumers (Cloud SQL, Memorystore) depend on this to ensure PSA exists first.
output "psa_connection" {
  value = google_service_networking_connection.psa.id
}
