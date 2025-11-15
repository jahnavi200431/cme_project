output "gke_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.gke.endpoint
}

output "postgres_ip" {
  description = "Public IP of the PostgreSQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}
