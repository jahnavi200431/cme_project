provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

data "google_client_config" "current" {}

locals {
  node_sa = "product-api-gsa@${var.project_id}.iam.gserviceaccount.com"
}

# ----------------------------
# IAM for Cloud SQL access
# ----------------------------
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.node_sa}"
}

# ----------------------------
# GKE Cluster
# ----------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  remove_default_node_pool = true
  initial_node_count       = 1
}

# ----------------------------
# Node pool
# ----------------------------
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

# ----------------------------
# Cloud SQL instance with Private IP
# ----------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled   = false
      private_network = "projects/${var.project_id}/global/networks/default"
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

# ----------------------------
# Service account key for Cloud SQL Proxy
# ----------------------------
resource "google_service_account_key" "cloudsql_proxy_key" {
  service_account_id = local.node_sa
}

# ----------------------------
# Kubernetes provider (after cluster is ready)
# ----------------------------
provider "kubernetes" {
  host                   = "https://${google_container_cluster.gke.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.gke.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

# ----------------------------
# Kubernetes Secret for Cloud SQL Proxy
# ----------------------------
resource "kubernetes_secret" "cloudsql_instance_credentials" {
  metadata {
    name      = "cloudsql-instance-credentials"
    namespace = "default"
  }

  data = {
    "key.json" = google_service_account_key.cloudsql_proxy_key.private_key
  }

  type = "Opaque"

  lifecycle {
    ignore_changes = [data]   # prevents errors if secret already exists
  }
}
