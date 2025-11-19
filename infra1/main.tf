provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------------------------------------------------------------
#  USE YOUR CUSTOM SERVICE ACCOUNT FOR GKE NODES
# ------------------------------------------------------------
locals {
  node_sa = "product-api-gsa@my-project-app-477009.iam.gserviceaccount.com"
}

# ------------------------------------------------------------
#  IAM PERMISSIONS FOR THE SERVICE ACCOUNT
# -------------------------------------------------------------

# Allow GKE nodes to write logs
resource "google_project_iam_member" "logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.node_sa}"
}

# Allow GKE nodes to write monitoring metrics
resource "google_project_iam_member" "metricwriter" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.node_sa}"
}

# Allow GKE nodes to access Cloud SQL
resource "google_project_iam_member" "cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.node_sa}"
}

# -------------------------------------------------------------
#  GKE CLUSTER
# -------------------------------------------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  network = "default"
}

# -------------------------------------------------------------
#  NODE POOL USING YOUR SERVICE ACCOUNT
# -------------------------------------------------------------
resource "google_container_node_pool" "node_pool" {
  name     = "api-node-pool"
  cluster  = google_container_cluster.gke.name
  location = var.zone

  node_config {
    machine_type    = "e2-medium"

    # ✔ Your custom service account
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
#  CLOUD SQL INSTANCE
# -------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true

      # ⚠️ Not modifying as per your request
      authorized_networks {
        name  = "any"
        value = "0.0.0.0/0"
      }
    }
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
