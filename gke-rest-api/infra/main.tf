terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Enable required APIs
resource "google_project_service" "enable_sql" {
  service = "sqladmin.googleapis.com"
}
resource "google_project_service" "enable_container" {
  service = "container.googleapis.com"
}
resource "google_project_service" "enable_artifact" {
  service = "artifactregistry.googleapis.com"
}

# Artifact Registry (Docker repo)
resource "google_artifact_registry_repository" "repo" {
  provider   = google
  location   = var.region
  repository_id = var.artifact_repo_name
  format     = "DOCKER"
  description = "Docker repo for gke-rest-api"
}

# Cloud SQL Postgres instance
resource "google_sql_database_instance" "postgres_instance" {
  name             = var.db_instance_name
  region           = var.region
  database_version = "POSTGRES_15"

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled = true
      # WARNING: demo uses 0.0.0.0/0 below. In production, replace with specific authorized networks or use private IP + VPC peering.
      authorized_networks {
        name  = "demo-allow"
        value = "0.0.0.0/0"
      }
    }
  }
}

resource "google_sql_database" "productdb" {
  name     = var.db_name
  instance = google_sql_database_instance.postgres_instance.name
}

resource "google_sql_user" "db_user" {
  instance = google_sql_database_instance.postgres_instance.name
  name     = var.db_user
  password = var.db_password
}

# GKE cluster
resource "google_container_cluster" "gke_cluster" {
  name               = var.gke_cluster_name
  location           = var.zone
  remove_default_node_pool = true
  initial_node_count = 1

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {}
}

resource "google_container_node_pool" "node_pool" {
  name     = "primary-pool"
  cluster  = google_container_cluster.gke_cluster.name
  location = var.zone

  node_count = 2

  node_config {
    machine_type = "e2-medium"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Create a GSA for the app and give Cloud SQL Client role
resource "google_service_account" "app_gsa" {
  account_id   = "product-api-gsa"
  display_name = "Product API GSA"
}

resource "google_project_iam_member" "gsa_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.app_gsa.email}"
}

# Outputs
output "artifact_repo" {
  value = google_artifact_registry_repository.repo.repository_id
}
output "cloudsql_public_ip" {
  value = google_sql_database_instance.postgres_instance.public_ip_address
}
output "cloudsql_conn_name" {
  value = google_sql_database_instance.postgres_instance.connection_name
}
output "gke_cluster_name" {
  value = google_container_cluster.gke_cluster.name
}
output "gsa_email" {
  value = google_service_account.app_gsa.email
}
