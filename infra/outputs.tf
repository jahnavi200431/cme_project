output "gke_endpoint" {
  description = "Endpoint of the GKE cluster"
  value       = google_container_cluster.gke.endpoint
}

# outputs.tf
output "db_instance_name" {
  description = "The name of the PostgreSQL Cloud SQL instance"
  value       = google_sql_database_instance.postgres.name
}

output "db_user" {
  description = "The username for the PostgreSQL database"
  value       = google_sql_user.db_user.name
}

output "db_password" {
    description = "The password for the PostgreSQL database"
  value     = google_secret_manager_secret_version.db_password_version.secret_data
  sensitive = true  # Hide sensitive information
}
