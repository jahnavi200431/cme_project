provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------- LOCALS ----------
locals {
  node_sa = "product-api-gsa@${var.project_id}.iam.gserviceaccount.com"
}

# -------- IAM for node service account (least-privilege for this simple setup) ----------
# Allow nodes/app SA to write logs and metrics and use Cloud SQL client
resource "google_project_iam_member" "nodes_logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.node_sa}"
}

resource "google_project_iam_member" "nodes_metricwriter" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.node_sa}"
}

resource "google_project_iam_member" "nodes_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.node_sa}"
}

# ----------------------------
# GKE cluster (minimal secure changes)
# ----------------------------
# This uses the existing network (default) to avoid creating duplicates.
# It configures Master Authorized Networks so only specified CIDR(s) can call the control plane API.
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  initial_node_count       = 1
  remove_default_node_pool = true
  deletion_protection      = false

  # use existing network/subnet (default). If you created secure VPC previously,
  # change these values to use it.
  network    = var.network    # default "default"
  subnetwork = var.subnetwork # default "default"

  # Master Authorized Networks: restrict control plane access to authorized CIDR
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = var.authorized_cidr
      display_name = "authorized_control_plane_network"
    }
  }

  ip_allocation_policy {}

  # keep logging/monitoring enabled
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
}

# Separate node pool — uses your existing service account (least-privilege)
resource "google_container_node_pool" "node_pool" {
  name     = "api-node-pool"
  cluster  = google_container_cluster.gke.name
  location = google_container_cluster.gke.location

  node_config {
    machine_type    = var.node_machine_type
    service_account = local.node_sa
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring"
    ]
  }

  initial_node_count = var.node_count
}

# ----------------------------
# Cloud SQL (unchanged network as requested)
# ----------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = var.db_tier

    ip_configuration {
      ipv4_enabled = true

      # NOTE: You requested no change to networking earlier; this leaves it open.
      authorized_networks {
        name  = "any"
        value = "0.0.0.0/0"
      }
    }
  }
}

resource "google_sql_database" "db" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_user" "root" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.postgres.name
}

# ----------------------------
# Outputs
# ----------------------------
output "gke_endpoint" {
  description = "GKE control plane endpoint (public, for clients allowed by master_authorized_networks)"
  value       = google_container_cluster.gke.endpoint
}

output "gke_master_authorized_cidr" {
  value = var.authorized_cidr
}

output "postgres_public_ip" {
  description = "Cloud SQL public IP (unchanged configuration)"
  value       = google_sql_database_instance.postgres.public_ip_address
}
