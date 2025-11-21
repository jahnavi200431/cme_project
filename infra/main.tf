provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
# VPC Network (Create if it doesn't exist)
# ------------------------------------------------------------
data "google_compute_network" "vpc_network" {
     name                   = "products-vpc"
    }
resource "google_compute_network" "vpc_network" {
  count                  = length(data.google_compute_network.vpc_network.id) > 0 ? 0 : 1
  name                   = "products-vpc"
  auto_create_subnetworks = false
}

# ------------------------------------------------------------
# Private Subnet in the VPC
# ------------------------------------------------------------

resource "google_compute_subnetwork" "private_subnet" {
  count         = length(google_compute_network.vpc_network) > 0 ? 1 : 0
  name          = "private-subnet"
  region        = var.region
  network       = google_compute_network.vpc_network[0].name
  ip_cidr_range = "10.0.0.0/24"
  depends_on    = [google_compute_network.vpc_network]
}

# ------------------------------------------------------------
# GKE Cluster (Create if the cluster does not exist)
# ------------------------------------------------------------

resource "google_container_cluster" "gke" {
  count                  = length(google_container_cluster.gke) > 0 ? 0 : 1
  name                   = "product-gke-cluster"
  location               = var.zone
  deletion_protection    = false
  remove_default_node_pool = true
  initial_node_count     = 1

  network    = google_compute_network.vpc_network[0].name
  subnetwork = google_compute_subnetwork.private_subnet[0].name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  master_authorized_networks_config {}

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [google_compute_subnetwork.private_subnet]
}

# ------------------------------------------------------------
# Cloud SQL Database Instance (Create if VPC exists)
# ------------------------------------------------------------

resource "google_sql_database_instance" "postgres" {
  count           = length(google_compute_network.vpc_network) > 0 ? 1 : 0
  name            = "product-db-instance"
  database_version = "POSTGRES_13"
  region          = var.region

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network[0].id
    }
  }

  depends_on = [google_compute_network.vpc_network]
}

# ------------------------------------------------------------
# Create Database
# ------------------------------------------------------------

resource "google_sql_database" "database" {
     count           = length(google_sql_database_instance.postgres) > 0 ? 1 : 0
  name     = var.db_name
  instance = google_sql_database_instance.postgres[0].name
  depends_on = [google_sql_database_instance.postgres]
}

# ------------------------------------------------------------
# Create DB User
# ------------------------------------------------------------

resource "google_sql_user" "db_user" {
       count           = length(google_sql_database_instance.postgres) > 0 ? 1 : 0
  name     = var.db_user
  instance = google_sql_database_instance.postgres[0].name
  password = data.google_secret_manager_secret_version.db_password.secret_data
  depends_on = [google_sql_database_instance.postgres]
}

# ------------------------------------------------------------
# Create Secret Manager Secret
# ------------------------------------------------------------

resource "google_secret_manager_secret" "db_password" {
  secret_id = "db-password"
  replication {
    auto {}
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes   = [secret_id]
  }
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}

# ------------------------------------------------------------
# Firewall Rule (Create if VPC exists)
# ------------------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  count                  = length(google_compute_network.vpc_network) > 0 ? 1 : 0
  name                   = "allow-internal-traffic"
  network                = google_compute_network.vpc_network[0].name
  direction              = "INGRESS"
  priority               = 1000

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["gke-node"]

  depends_on = [google_compute_network.vpc_network]
}

# ------------------------------------------------------------
# Cloud SQL Proxy Setup (for secure access)
# ------------------------------------------------------------
/* resource "google_container_cluster" "gke_with_sql_proxy" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name
  initial_node_count       = 1

  private_cluster_config {
    enable_private_nodes    = true   # Enable private nodes
    enable_private_endpoint = true   # Enable private endpoint for the master
  }

  # Configure master authorized networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = "0.0.0.0/0"  # Allow all networks (use more restrictive ranges if needed)
      display_name = "Allow All"
    }
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
} */
