provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------------------------------------------------------------
#  EXISTING SERVICE ACCOUNT (Your chosen SA)
# -------------------------------------------------------------
# No need to create it — we just reference it
locals {
  existing_node_sa = "433503387155-compute@developer.gserviceaccount.com"
}

# -------------------------------------------------------------
#  GKE CLUSTER (Workload Identity optional)
# -------------------------------------------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  network = "default"

  # (Optional) Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# -------------------------------------------------------------
#  NODE POOL USING EXISTING SERVICE ACCOUNT
# -------------------------------------------------------------
resource "google_container_node_pool" "node_pool" {
  name     = "api-node-pool"
  cluster  = google_container_cluster.gke.name
  location = var.zone

  node_config {
    machine_type    = "e2-small"

    # Use your chosen service account
    service_account = local.existing_node_sa

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  initial_node_count = 2
}

# -------------------------------------------------------------
#  CLOUD SQL — unchanged (you asked not to modify networking)
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
