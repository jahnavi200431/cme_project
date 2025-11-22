provider "google" {
  project = var.project_id
  region  = var.region_name
}

# Create the VPC Network
resource "google_compute_network" "vpc_network" {
  name                   = var.vpc_name
}

# Create the Private Subnet
resource "google_compute_subnetwork" "private_subnet" {
  name                      = var.subnet_name
  region                    = var.region_name
  network                   = google_compute_network.vpc_network.id
  ip_cidr_range             = "10.10.0.0/24"
  private_ip_google_access = true
}


# Create the Cloud SQL Database Instance
resource "google_sql_database_instance" "db_instance" {
  name             = var.db_instance_name
  database_version = "POSTGRES_15"
  region           = var.region_name

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.self_link
    }
  }
}

# Fetch the password from Google Cloud Secret Manager
data "google_secret_manager_secret_version" "db_password" {
  secret  = "db-password"
}

# Create Database
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
}

# Create DB User
resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.db_instance.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}

# Create the Kubernetes Cluster
resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.zone_name
  deletion_protection      = false
  remove_default_node_pool = false
  initial_node_count       = 1
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name

   private_cluster_config {
     enable_private_nodes = true
     enable_private_endpoint = false
   }
}

## Firewall Rule (Create if VPC exists)
resource "google_compute_firewall" "allow_internal" {
  name       = var.frewall_name
  network    = google_compute_network.vpc_network.name
  direction  = "INGRESS"
  priority   = 1000
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.0.0.0/24"]
  target_tags   = ["gke-node"]
}




# ------------------------------------------------------------
# Cloud SQL Proxy Setup (for secure access)
# ------------------------------------------------------------
/* resource "google_container_cluster" "gke_with_sql_proxy" {
  name                     = "product-gke-cluster"
  location                 = var.zone_name
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
