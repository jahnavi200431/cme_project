provider "google" {
  project = var.project_id
  region  = var.region_name
}

## Create the VPC Network
data "google_compute_network" "vpc_network" {
  name                   = var.vpc_name
}
data "google_compute_subnetwork" "private_subnet" {
     name                      = var.subnet_name
    }
/*
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
 */


/*
resource "google_compute_network" "vpc_network" {
  name                   = var.vpc_name
}

# Create the Private Subnet
resource "google_compute_subnetwork" "private_subnet" {
  name                      = var.subnet_name
  region                    = var.region_name
  network                   = google_compute_network.vpc_network.id
  ip_cidr_range             = "10.10.0.0/24"
  private_ip_google_access  = true  # Enable Private Google Access
}
 */


# Create the Private Services Connection for Cloud SQL
/* resource "google_compute_service_attachment" "private_services_connection" {
  name            = "private-services-connection"
  region          = var.region_name
  target_service  = "services/servicenetworking.googleapis.com"  # Private service network for Cloud SQL

  # Connection preference - typically, you would use 'PREFERRED' for Cloud SQL
  connection_preference = "PREFERRED"

  # NAT subnets that will be used for Private Google Access
  nat_subnets = [
    data.google_compute_subnetwork.private_subnet.id
  ]

  # Enable Proxy Protocol (typically set to false unless needed for specific use cases)
  enable_proxy_protocol = false
} */

# Create the Kubernetes Cluster
/*  resource "google_container_cluster" "cluster" {
  name                     = var.cluster_name
  location                 = var.zone_name
  deletion_protection      = false
  remove_default_node_pool = false
  initial_node_count       = 1
  network                  = data.google_compute_network.vpc_network.name
  subnetwork               = data.google_compute_subnetwork.private_subnet.name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Private endpoint is set to false
  }

  depends_on = [data.google_compute_network.vpc_network, data.google_compute_subnetwork.private_subnet]
} */
# Create the Cloud SQL Database Instance with Private IP
# Reserve a global IP address for Private Services Access

# Reserve a global IP address for Private Services Access
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

/*   depends_on = [
    google_service_networking_connection.private_service_connect
  ] */
}

## Fetch the password from Google Cloud Secret Manager
data "google_secret_manager_secret_version" "db_password" {
  secret  = "db-password"
}

# Create Database
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.db_instance.name
}

# Create DB User
resource "google_sql_user" "db_user" {
  name     = var.db_user
  instance = google_sql_database_instance.db_instance.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}
# Firewall Rule to allow access to Cloud SQL via private IP
/* resource "google_compute_firewall" "allow_internal" {
  name       = var.firewall_name
  network    = data.google_compute_network.vpc_network.name
  direction  = "INGRESS"
  priority   = 1000
  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.10.0.0/24"]  # Allow only from your internal network
  target_tags   = ["gke-node"]
} */



# ------------------------------------------------------------
# Cloud SQL Proxy Setup (for secure access)
# ------------------------------------------------------------
/* resource "google_container_cluster" "gke_with_sql_proxy" {
  name                     = "product-gke-cluster"
  location                 = var.zone_name
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name
  initial_node_count       = 1

  private_cluster_config {
    enable_private_nodes    = true   # Enable private nodes
    enable_private_endpoint = true   # Enable private endpoint for the master
  }

  # Configure master authorized networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = "0.0.0.0/0"  # Allow all networks (use more restrictive ranges if needed)
      display_name = "Allow All"
    }
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
} */