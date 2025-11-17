provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------------------------------------------------------------
#  USE YOUR CUSTOM SERVICE ACCOUNT FOR GKE NODES
# -------------------------------------------------------------
locals {
  node_sa = "product-api-gsa@my-project-app-477009.iam.gserviceaccount.com"
}

# -------------------------------------------------------------
#  IAM PERMISSIONS FOR THE SERVICE ACCOUNT
# -------------------------------------------------------------
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

# -------------------------------------------------------------
#  USE EXISTING VPC & SUBNET (NO CREATION → NO QUOTA ERROR)
# -------------------------------------------------------------
data "google_compute_network" "gke_vpc" {
  name = "default"
}

data "google_compute_subnetwork" "gke_subnet" {
  name   = "default"
  region = var.region
}

# -------------------------------------------------------------
#  UPDATED GKE CLUSTER (PRIVATE NODES + PUBLIC ENDPOINT)
# -------------------------------------------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = data.google_compute_network.gke_vpc.self_link
  subnetwork = data.google_compute_subnetwork.gke_subnet.self_link

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # MUST remain false to allow kubectl & Cloud Build
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      display_name = "admin-access"
      cidr_block   = var.admin_ip_cidr   # your laptop IP /32
    }

    cidr_blocks {
      display_name = "google-cloud"
      cidr_block   = "35.235.240.0/20"   # required for GKE API
    }
  }

  ip_allocation_policy {}
}

# -------------------------------------------------------------
#  NODE POOL USING YOUR SERVICE ACCOUNT
# -------------------------------------------------------------
resource "google_container_node_pool" "node_pool" {
  name     = "api-node-pool"
  cluster  = google_container_cluster.gke.name
  location = var.zone

  node_config {
    machine_type    = "e2-small"
    service_account = local.node_sa

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  initial_node_count = 2
}

# -------------------------------------------------------------
#  CLOUD SQL INSTANCE (UNCHANGED)
# -------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true

      authorized_networks {
        name  = "any"
        value = "0.0.0.0/0"
      }
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
