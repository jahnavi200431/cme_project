
output "db_password" {
    description = "The password for the PostgreSQL database"
  value     = data.google_secret_manager_secret_version.db_password.secret_data
  sensitive = true  # Hide sensitive information
}
