output "gke_endpoint" {
  value = google_container_cluster.gke[count.index].endpoint  # Use count.index
}

# outputs.tf
output "db_instance_name" {
    description = "The name of the PostgreSQL Cloud SQL instance"
  value = google_sql_database_instance.postgres[count.index].name  # Use count.index
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
