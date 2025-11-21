provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
# VPC Network (Create if it doesn't exist)
# ------------------------------------------------------------

data "google_compute_network" "vpc_network" {
  name                   = var.vpc_name
  auto_create_subnetworks = false
}

# ------------------------------------------------------------
# Private Subnet in the VPC
# ------------------------------------------------------------
data "google_compute_subnetwork" "private_subnet" {
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.0.0.0/24"
  depends_on    = [google_compute_network.vpc_network]
}

# ------------------------------------------------------------
# GKE Cluster (Create if not already present)
# ------------------------------------------------------------
# Data source to check if the GKE cluster exists

resource "google_container_cluster" "cluster" {
  name                   = var.cluster_name
  location               = var.zone
  deletion_protection    = false
  remove_default_node_pool = true

  node_pool {
    name               = "default-node-pool"
    initial_node_count = 1

    node_config {
      machine_type = "e2-micro"
    }
  }

  network    = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.private_subnet.name

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
# Create the node pool (which Terraform manages)
resource "google_container_node_pool" "node_pool" {
  cluster   = google_container_cluster.cluster.name
  location  = var.zone
  node_count = 3

  node_config {
    machine_type = "e2-micro"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
# ------------------------------------------------------------
# Cloud SQL Database Instance (Create if VPC exists)
# ------------------------------------------------------------
resource "google_sql_database_instance" "db_instance" {
  name            = var.db_instance_name
  database_version = "POSTGRES_13"
  region          = var.region

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }
  }

  depends_on = [google_compute_network.vpc_network]
}

# ------------------------------------------------------------
# Fetch the password from Google Cloud Secret Manager
# ------------------------------------------------------------
data "google_secret_manager_secret_version" "db_password" {
  secret = "db-password"  # Update with the correct secret name
}

# ------------------------------------------------------------
# Create Database
# ------------------------------------------------------------
resource "google_sql_database" "database" {
  name            = var.db_name
  instance        = google_sql_database_instance.db_instance.name
  depends_on      = [google_sql_database_instance.db_instance]
}

# ------------------------------------------------------------
# Create DB User
# ------------------------------------------------------------
resource "google_sql_user" "db_user" {
  name            = var.db_user
  instance        = google_sql_database_instance.db_instance.name
  password        = data.google_secret_manager_secret_version.db_password.secret_data
  depends_on      = [google_sql_database_instance.db_instance]
}

# ------------------------------------------------------------
# Firewall Rule (Create if VPC exists)
# ------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name                   = "allow-internal-traffic"
  network                = google_compute_network.vpc_network.name
  direction              = "INGRESS"
  priority               = 1000

  allow {
    protocol = "tcp"
    ports    = ["5432"]
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
