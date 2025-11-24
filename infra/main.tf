# ---------------------------
# PROVIDER
# ---------------------------
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.region_name
  zone    = var.zone_name
}

# ---------------------------
# DATA SOURCES
# ---------------------------
data "google_compute_network" "vpc_network" {
  name = var.vpc_name
}

data "google_compute_subnetwork" "private_subnet" {
  name   = var.subnet_name
  region = var.region_name
}



# ---------------------------
# GKE CLUSTER
# ---------------------------
resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.zone_name
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = data.google_compute_network.vpc_network.self_link
  subnetwork = data.google_compute_subnetwork.private_subnet.self_link

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

workload_identity_config {
    identity_namespace = "${var.project_id}.svc.id.goog"
  }
  
  depends_on = [
    data.google_compute_network.vpc_network,
    data.google_compute_subnetwork.private_subnet
  ]

}

resource "google_container_node_pool" "primary_nodes" {
  name       = "cloudsql-pool"
  cluster    = google_container_cluster.cluster.name
  location   = var.zone_name
  node_count = 2

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
    tags = ["gke-node"]
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 2
  }

  depends_on = [
    google_container_cluster.cluster
  ]
}

# ---------------------------
# CLOUD SQL INSTANCE PRIVATE IP
# ---------------------------
resource "google_sql_database_instance" "db_instance" {
  name             = var.db_instance_name
  database_version = "POSTGRES_15"
  region           = var.region_name

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      # Uses the existing PSA connection automatically
      private_network = data.google_compute_network.vpc_network.self_link
      ipv4_enabled    = false
    }
  }
}

data "google_secret_manager_secret_version" "db_password" {
  secret = "db-password"
}

resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
}

resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.db_instance.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}


# ----------- FIREWALL -----------------

resource "google_compute_firewall" "allow_internal" {
  name       = var.firewall_name
  network    = data.google_compute_network.vpc_network.name
  direction  = "INGRESS"
  priority   = 1000

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.10.0.0/24"]
  target_tags   = ["gke-node"]
}

