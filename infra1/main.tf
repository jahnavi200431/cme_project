provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
# VPC and Subnet Configuration
# ------------------------------------------------------------
resource "google_compute_network" "vpc_network" {
  name                    = "product-vpc"
  auto_create_subnetworks  = false
}

# Private subnet in the VPC
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "private-subnet"
  region                   = var.region
  network                  = google_compute_network.vpc_network.name
  ip_cidr_range            = "10.0.0.0/24"  # Adjust the CIDR range as per your requirements
  private_ip_google_access = true  # Enable Private Google Access
}

# ------------------------------------------------------------
# IAM Permissions for the Service Account
# ------------------------------------------------------------

locals {
  node_sa = "product-api-gsa@my-project-app-477009.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.node_sa}"
}

resource "google_project_iam_member" "metricwriter" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.node_sa}"
}

resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.node_sa}"
}

# ------------------------------------------------------------
# GKE Cluster (with private access to Cloud SQL)
# ------------------------------------------------------------
resource "google_container_cluster" "gke" {
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
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false  # Disable public IP for Cloud SQL
      private_network = google_compute_network.vpc_network.self_link  # Link to VPC network
    }

    # Move deletion_protection inside the settings block
    #deletion_protection = false  # Correct location for this argument
  }
}



# Create DB
resource "google_sql_database" "db" {
  name     = "productdb"
  instance = google_sql_database_instance.postgres.name
}

# Create DB user
resource "google_sql_user" "root" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.postgres.name
}

# ------------------------------------------------------------
# Firewall Rules to allow GKE to access Cloud SQL privately
# ------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name      = "allow-internal-traffic"
  network   = google_compute_network.vpc_network.name
  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["3306"]  # Adjust port based on Cloud SQL or other application
  }

  source_ranges = ["10.0.0.0/24"]  # Allow internal network traffic within VPC

  target_tags = ["gke-node"]
}

# ------------------------------------------------------------
# Cloud SQL Proxy Setup (for secure access)
# ------------------------------------------------------------
resource "google_container_cluster" "gke_with_sql_proxy" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name
  initial_node_count       = 1

  private_cluster_config {
    enable_private_nodes    = true   # Correct argument name (plural)
    enable_private_endpoint = true
    }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}
