provider "google" {
  project = var.project_id
  region  = var.region_name
}

data "google_compute_network" "vpc_network" {
  name = var.vpc_name
}

data "google_compute_subnetwork" "private_subnet" {
  name = var.subnet_name
}

resource "google_service_networking_connection" "private_service_connect" {
  network                 = data.google_compute_network.vpc_network.self_link
  service                 = "services/servicenetworking.googleapis.com"
  reserved_peering_ranges = ["privateip"]  # <-- FIXED
}

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

  depends_on = [google_service_networking_connection.private_service_connect]
}
