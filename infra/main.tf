provider "google" {
  project = var.project_id
  region  = var.region_name
}

data "google_compute_network" "vpc_network" {
  name = var.vpc_name
}

data "google_compute_subnetwork" "private_subnet" {
  name   = var.subnet_name
  region = var.region_name
}

# ----------- PRIVATE SERVICE CONNECT (Cloud SQL) -----------------

resource "google_compute_global_address" "private_ip_range" {
  name          = "private-ip-range1"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = data.google_compute_network.vpc_network.self_link
}

resource "google_service_networking_connection" "private_service_connect" {
  network                 = data.google_compute_network.vpc_network.self_link
  service                 = "services/servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ----------- GKE CLUSTER -----------------

resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.zone_name
  deletion_protection      = false
  remove_default_node_pool = false
  initial_node_count       = 1

  network    = data.google_compute_network.vpc_network.self_link
  subnetwork = data.google_compute_subnetwork.private_subnet.self_link

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  depends_on = [
    data.google_compute_network.vpc_network,
    data.google_compute_subnetwork.private_subnet
  ]
}


# ----------- CLOUD SQL INSTANCE PRIVATE IP -----------------

resource "google_sql_database_instance" "db_instance" {
  name             = var.db_instance_name
  database_version = "POSTGRES_15"
  region           = var.region_name

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      private_network = data.google_compute_network.vpc_network.self_link
      ipv4_enabled    = false
    }
  }

  depends_on = [
    google_service_networking_connection.private_service_connect
  ]
}

# ----------- SECRET MANAGER -----------------

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
