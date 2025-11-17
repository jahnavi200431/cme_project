output "gke_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.gke.endpoint
}

output "postgres_public_ip" {
  description = "Public IP address of the PostgreSQL instance"
  value       = google_sql_database_instance.postgres.public_ip_address
}


output "node_service_account" {
  description = "Service account used by the GKE node pool"
  value       = local.node_sa
}
