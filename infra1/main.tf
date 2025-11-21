provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
# PUBLIC Cloud SQL Instance (PostgreSQL)
# ------------------------------------------------------------
resource "google_sql_database_instance" "db_instance" {
  name             = var.db_instance_name
  database_version = "POSTGRES_13"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true     # 🌎 ENABLE PUBLIC IP
      # Allow everyone (NOT SAFE — but you requested public)
      authorized_networks {
        name  = "public-access"
        value = "0.0.0.0/0"
      }
    }
  }
}

# ------------------------------------------------------------
# Fetch DB password from Secret Manager
# ------------------------------------------------------------
data "google_secret_manager_secret_version" "db_password" {
  secret = "db-password"
}

# ------------------------------------------------------------
# Create DB + User
# ------------------------------------------------------------
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
}

resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.db_instance.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}

# ------------------------------------------------------------
# FULL PUBLIC GKE CLUSTER
# ------------------------------------------------------------
resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.zone
  deletion_protection      = false
  remove_default_node_pool = false
  initial_node_count       = 1

  # 🌎 PUBLIC NETWORKING (default VPC)
  network    = "default"
  subnetwork = "default"

  # 🟢 Public control plane
  private_cluster_config {
    enable_private_nodes    = false
    enable_private_endpoint = false
  }

  # Allow any address to reach master API (NOT SAFE)
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "public-open"
    }
  }
}
