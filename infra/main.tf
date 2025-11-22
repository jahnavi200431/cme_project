provider "google" {
  project = var.project_id
  region  = var.region_name
}

# Create the VPC Network
data "google_compute_network" "vpc_network" {
  name                   = var.vpc_name
}
data "google_compute_subnetwork" "private_subnet" {
     name                      = var.subnet_name
    }
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

# Reserve a global IP address for the Private Services Access (Cloud SQL)
resource "google_compute_global_address" "private_services_ip" {
  name    = "private-services-ip"
  purpose = "VPC_PEERING"  # This ensures it's used for private services access
}

# Create the Private Services Connection (Service Attachment)
resource "google_compute_service_attachment" "private_services_connection" {
  name               = "private-services-connection"
  region             = var.region_name
  project            = var.project_id
  target_service     = "services/servicenetworking.googleapis.com"  # Private service endpoint for Cloud SQL

  # Connection preference - 'PREFERRED' for Cloud SQL
  connection_preference = "PREFERRED"

  # Specify the NAT subnets for Private Google Access
  nat_subnets = [
    data.google_compute_subnetwork.private_subnet.id
  ]

  # Proxy Protocol for this connection (set to false unless necessary)
  enable_proxy_protocol = false
}

# Create the Cloud SQL Database Instance with Private IP
resource "google_sql_database_instance" "db_instance" {
  name             = var.db_instance_name
  database_version = "POSTGRES_15"
  region           = var.region_name

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false  # No external IP
      private_network = data.google_compute_network.vpc_network.id  # Full network URL
    }
  }

  depends_on = [google_compute_service_attachment.private_services_connection]
}
# Fetch the password from Google Cloud Secret Manager
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
