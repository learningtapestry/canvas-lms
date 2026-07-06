output "host" {
  value = google_redis_instance.this.host
}

output "port" {
  value = google_redis_instance.this.port
}

output "auth_string" {
  description = "Redis AUTH password (feed into redis.yml)"
  value       = google_redis_instance.this.auth_string
  sensitive   = true
}
