/*
output "gke_endpoint" {
  value = google_container_cluster.gke.endpoint  # Direct reference without count.index
}

output "db_instance_name" {
  value = google_sql_database_instance.postgres.name  # Direct reference without count.index
}
 */

/*
output "db_user" {
  description = "The username for the PostgreSQL database"
  value       = google_sql_user.db_user.name
}
 */

output "db_password" {
    description = "The password for the PostgreSQL database"
  value     = data.google_secret_manager_secret_version.db_password.secret_data
  sensitive = true  # Hide sensitive information
}
