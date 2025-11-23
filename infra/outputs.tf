output "gke_endpoint" {
  value = google_container_cluster.cluster.endpoint
}

output "db_instance" {
  value = google_sql_database_instance.db_instance.name
}

output "db_user" {
  description = "The username for the PostgreSQL database"
  value       = google_sql_user.db_user.name
}

 

output "db_password" {
    description = "The password for the PostgreSQL database"
  value     = data.google_secret_manager_secret_version.db_password.secret_data
  sensitive = true  
}
