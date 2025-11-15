provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------------------
# Create GKE Cluste
# -------------------
resource "google_container_cluster" "gke" {
  name     = "product-gke-cluster"
  location = var.zone
  deletion_protection = false
  remove_default_node_pool = true
  initial_node_count       = 2

  network = "default"
}

# Node Pool
resource "google_container_node_pool" "node_pool" {
  name       = "api-node-pool"
  cluster    = google_container_cluster.gke.name
  location   = var.zone

  node_config {
    machine_type = "e2-small"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  initial_node_count = 2
}

# -------------------
# Create PostgreSQL (Cloud SQL)
# -------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    # Enable public IP for simple testing 
    # Remove this & use private IP for production
    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
    name  = "any"
    value = "34.42.255.232"
  }
    }
  }
}

# Create initial database
resource "google_sql_database" "db" {
  name     = "productdb"
  instance = google_sql_database_instance.postgres.name
}

# Create Postgres user
resource "google_sql_user" "root" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.postgres.name
}
