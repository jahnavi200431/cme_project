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
#  GKE CLUSTER
# -------------------------------------------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  network = "default"

  private_cluster_config {
    enable_private_nodes     = true
    enable_private_endpoint  = false
    master_ipv4_cidr_block   = "172.16.0.0/28"
  }
}

# -------------------------------------------------------------
#  NODE POOL USING YOUR SERVICE ACCOUNT
# -------------------------------------------------------------
resource "google_container_node_pool" "private_node_pool1" {
  name     = "private-node-pool1"
  cluster  = google_container_cluster.gke.name
  location = var.zone

  initial_node_count = 2

  node_config {
    machine_type    = "e2-medium"
    disk_size_gb    = 50
    disk_type       = "pd-standard"
    service_account = local.node_sa

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      type = "private"
    }
  }

  management {
    auto_upgrade = true
    auto_repair  = false
  }
}

# -------------------------------------------------------------
#  CLOUD NAT FOR PRIVATE NODES
# -------------------------------------------------------------
resource "google_compute_router" "nat_router1" {
  name    = "nat-router1"
  network = "default"
  region  = var.region
}

resource "google_compute_router_nat" "nat_config1" {
  name                              = "nat-config1"
  router                            = google_compute_router.nat_router.name
  region                            = google_compute_router.nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# -------------------------------------------------------------
#  CLOUD SQL INSTANCE (PUBLIC)
# -------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = true

      # Allow connections from anywhere (0.0.0.0/0)
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
