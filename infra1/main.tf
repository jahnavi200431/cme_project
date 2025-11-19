provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  node_sa = "product-api-gsa@${var.project_id}.iam.gserviceaccount.com"
}

# Create IAM bindings for the service account
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.node_sa}"
}

# GKE Cluster
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1
}

# Node pool
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

# Cloud SQL instance
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled = false
    }
  }
}

# Database
resource "google_sql_database" "db" {
  name     = "productdb"
  instance = google_sql_database_instance.postgres.name
}

# DB user
resource "google_sql_user" "root" {
  name     = var.db_user
  password = var.db_password
  instance = google_sql_database_instance.postgres.name
}

# Service account key for Cloud SQL Proxy
resource "google_service_account_key" "cloudsql_proxy_key" {
  service_account_id = local.node_sa
}

# Kubernetes provider
provider "kubernetes" {
  host                   = google_container_cluster.gke.endpoint
  cluster_ca_certificate = base64decode(google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

data "google_client_config" "current" {}

# Kubernetes secret for proxy key
resource "kubernetes_secret" "cloudsql_instance_credentials" {
  metadata {
    name      = "cloudsql-instance-credentials"
    namespace = "default"
  }

  data = {
    "key.json" = google_service_account_key.cloudsql_proxy_key.private_key
  }

  type = "Opaque"
}
