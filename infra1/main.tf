provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------------------
# Create GKE Cluster (Private VPC-native)
# -------------------
resource "google_container_cluster" "gke" {
  name                  = "product-gke-cluster"
  location              = var.zone
  remove_default_node_pool = true
  deletion_protection   = false

  network    = "default"
  subnetwork = "default"

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  initial_node_count = 1
}

resource "google_container_node_pool" "node_pool" {
  name     = "api-node-pool"
  cluster  = google_container_cluster.gke.name
  location = var.zone

  node_config {
    machine_type = "e2-small"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  initial_node_count = 2
}

# -------------------
# Cloud SQL with PRIVATE IP ONLY
# -------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false  # 🔒 disable public IP
      private_network = "projects/${var.project_id}/global/networks/default"
    }
  }
}

resource "google_sql_database" "db" {
  name     = "productdb"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "root" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.postgres.name
}
