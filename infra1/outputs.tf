output "gke_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.gke.endpoint
}

output "postgres_ip" {
  description = "Public IP of the PostgreSQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}

output "gke_node_service_account" {
  description = "GKE Node Service Account email"
  value       = google_service_account.gke_nodes.email
}

output "gke_app_service_account" {
  description = "GKE App Workload Identity Service Account email"
  value       = google_service_account.app_sa.email
}
