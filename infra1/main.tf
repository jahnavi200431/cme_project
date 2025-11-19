provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -------------------------------------------------------------
# Locals
# -------------------------------------------------------------
locals {
  node_sa = "product-api-gsa@${var.project_id}.iam.gserviceaccount.com"
}

# -------------------------------------------------------------
# IAM: give minimal node permissions needed (logging/monitoring/cloudsql)
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
# GKE CLUSTER (managed here) - BE CAREFUL IF CLUSTER ALREADY EXISTS
# -------------------------------------------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  network                  = "default"
  remove_default_node_pool = true
  initial_node_count       = 1

  # If your cluster is already configured differently, consider importing
  # the existing cluster into Terraform state instead of applying to avoid
  # replacement. See notes below.

  # Do NOT set private_cluster_config here unless you intend to create a private control plane.
  # (You previously used private endpoints; keep this minimal to avoid accidental replacement.)
}

# Prevent accidental destroy/recreate of cluster attributes managed outside TF
# (optional — adjust if you plan to fully manage cluster in Terraform)
resource "null_resource" "gke_marker" {
  triggers = {
    cluster_id = google_container_cluster.gke.id
  }
  lifecycle {
    prevent_destroy = true
  }
}

# -------------------------------------------------------------
# NODE POOL USING YOUR SERVICE ACCOUNT
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

  lifecycle {
    # if this pool already exists and you imported it, keep this optionally
    ignore_changes = [
      # ignore fields that can change outside terraform
    ]
  }
}

# -------------------------------------------------------------
# CLOUD NAT (so private nodes can access public internet e.g. to pull images)
# -------------------------------------------------------------
resource "google_compute_router" "nat_router" {
  name    = "nat-router"
  network = "default"
  region  = var.region
}

resource "google_compute_router_nat" "nat_config" {
  name                              = "nat-config"
  router                            = google_compute_router.nat_router.name
  region                            = google_compute_router.nat_router.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# -------------------------------------------------------------
# CLOUD SQL INSTANCE (public IP allowed for your IP)
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
        name  = "cloudshell-or-my-ip"
        value = "45.118.72.149/32"   # <--- your allowed CIDR
      }
    }
  }

  # Avoid accidental replacement: do not set deletion_protection = false unless you want deletions possible
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

# -------------------------------------------------------------
# Outputs (helpful)
# -------------------------------------------------------------
output "gke_cluster_name" {
  value = google_container_cluster.gke.name
}

output "node_pool_name" {
  value = google_container_node_pool.private_node_pool1.name
}

output "nat_router" {
  value = google_compute_router.nat_router.name
}
