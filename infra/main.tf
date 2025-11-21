provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
## VPC and Subnet Configuration
# ------------------------------------------------------------
# Only create the VPC network if it does not exist
# Declare a data block to check for the existing VPC network
data "google_compute_network" "vpc_network" {
  name = "products-vpc"  # Replace with your actual VPC name
}

# Create the VPC network if it doesn't exist
resource "google_compute_network" "vpc_network" {
  count                  = length(data.google_compute_network.vpc_network.id) > 0 ? 0 : 1
  name                   = "products-vpc"
  auto_create_subnetworks = false
}
# Private subnet in the VPC
resource "google_compute_subnetwork" "private_subnet" {
  count          = google_compute_network.vpc_network.*.name != [] ? 1 : 0  # Ensure count is set
  name           = "private-subnet"
  region         = var.region
  network        = google_compute_network.vpc_network[count.index].name  # Correctly use count.index
  ip_cidr_range  = "10.0.0.0/24"
}

# ------------------------------------------------------------
# GKE Cluster (with private access to Cloud SQL)
# ------------------------------------------------------------
resource "google_container_cluster" "gke" {
    count                  = length(data.google_container_cluster.gke.id) > 0 ? 0 : 1
  name                     = "product-gke-cluster"
  location                 = var.zone
  deletion_protection      = false   # Set to false to allow deletion
  remove_default_node_pool = true
  initial_node_count       = 1

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
}

# ------------------------------------------------------------
# Cloud SQL Instance with Private IP
# ------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  count           = google_compute_network.vpc_network.*.name != [] ? 1 : 0  # Ensure count is set
  name            = "product-db-instance"
  database_version = "POSTGRES_13"
  region          = var.region

  settings {
    tier = "db-f1-micro"  # Small instance size
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network[count.index].id  # Use count.index to reference network
    }
  }
}
# Create DB
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
   lifecycle {
      ignore_changes = [name]  # Ignore changes to the cluster name
    }
}

# Create DB user

resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.postgres.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
   lifecycle {
      ignore_changes = [name]  # Ignore changes to the cluster name
    }
}


resource "google_secret_manager_secret" "db_password" {
  secret_id = "db-password"

  replication {
     auto {}  # This specifies that the secret will be automatically replicated across all regions
   }
  lifecycle {
    prevent_destroy = true  # Prevents destruction of the secret
    ignore_changes   = [secret_id]  # Avoid changes to the secret_id if it already exists
  }
}


# Declare the secret version
resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password  # You should set this variable in terraform.tfvars or at runtime
}
# ------------------------------------------------------------
# Firewall Rules to allow GKE to access Cloud SQL privately
# ------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  count      = google_compute_network.vpc_network.*.name != [] ? 1 : 0  # Ensure count is set
  name       = "allow-internal-traffic"
  network    = google_compute_network.vpc_network[count.index].name  # Use count.index to reference network
  direction  = "INGRESS"
  priority   = 1000

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  source_ranges = ["10.0.0.0/24"]  # Allow internal network traffic within VPC

  target_tags = ["gke-node"]
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
