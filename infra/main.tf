provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
# VPC Network
# ------------------------------------------------------------
resource "google_compute_network" "vpc_network" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# ------------------------------------------------------------
# Private Subnet
# ------------------------------------------------------------
resource "google_compute_subnetwork" "private_subnet" {
  name                     = var.subnet_name
  region                   = var.region
  network                  = google_compute_network.vpc_network.name
  ip_cidr_range            = "10.0.0.0/24"
  private_ip_google_access = true
}

# ------------------------------------------------------------
# Allocate IP range for Private Services Access (for Cloud SQL)
# ------------------------------------------------------------
resource "google_compute_global_address" "private_services_ip" {
  name          = "private-services-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.name
}

# ------------------------------------------------------------
# Setup Private Services Connection
# ------------------------------------------------------------
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services_ip.name]
}

# ------------------------------------------------------------
# GKE Cluster
# ------------------------------------------------------------
resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  master_authorized_networks_config {}
}

# ------------------------------------------------------------
# Node Pool for App + Cloud SQL Proxy
# ------------------------------------------------------------
resource "google_container_node_pool" "app_node_pool" {
  name       = "app-node-pool"
  cluster    = google_container_cluster.cluster.name
  location   = var.zone
  node_count = 2

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    tags         = ["gke-node"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_container_cluster.cluster]
}

# ------------------------------------------------------------
# Node Pool for Cloud Build private workers
# ------------------------------------------------------------
resource "google_container_node_pool" "cloudbuild_node_pool" {
  name       = "cloudbuild-node-pool"
  cluster    = google_container_cluster.cluster.name
  location   = var.zone
  node_count = 1

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    tags         = ["cloudbuild-node"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_container_cluster.cluster]
}

# ------------------------------------------------------------
# Cloud SQL PostgreSQL Instance (Private IP only)
# ------------------------------------------------------------
resource "google_sql_database_instance" "db_instance" {
  name             = var.db_instance_name
  database_version = "POSTGRES_13"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# ------------------------------------------------------------
# Database creation
# ------------------------------------------------------------
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
}

# ------------------------------------------------------------
# Fetch DB password from Secret Manager
# ------------------------------------------------------------
data "google_secret_manager_secret_version" "db_password" {
  secret = "db-password"
}

# ------------------------------------------------------------
# Create DB user
# ------------------------------------------------------------
resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.db_instance.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}

# ------------------------------------------------------------
# Firewall to allow internal traffic to Cloud SQL
# ------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-traffic"
  network = google_compute_network.vpc_network.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["gke-node"]
}
