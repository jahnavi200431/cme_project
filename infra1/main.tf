provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ------------------------------------------------------------
# VPC and Subnet Configuration
# ------------------------------------------------------------
resource "google_compute_network" "vpc_network" {
  name                    = "product-vpc"
  auto_create_subnetworks  = false
}

# Private subnet in the VPC
resource "google_compute_subnetwork" "private_subnet" {
  name          = "private-subnet"
  region        = var.region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.0.0.0/24"  # Adjust the CIDR range as per your requirements
  private_ip_google_access = true  # Enable Private Google Access
}

# ------------------------------------------------------------
# IAM Permissions for the Service Account
# ------------------------------------------------------------

locals {
  node_sa = "product-api-gsa@my-project-app-477009.iam.gserviceaccount.com"
}

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

# ------------------------------------------------------------
# GKE Cluster (with private access to Cloud SQL)
# ------------------------------------------------------------
resource "google_container_cluster" "gke" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1

  network = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.private_subnet.name

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  master_authorized_networks_config {
    enabled = false
  }

  # Disable legacy GKE metadata server
  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

}

# ------------------------------------------------------------
# Cloud SQL Instance with Private IP
# ------------------------------------------------------------
resource "google_sql_database_instance" "postgres" {
  name             = "product-db-instance"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled = false  # Disable public IP for Cloud SQL
      private_network = google_compute_network.vpc_network.self_link  # Link to VPC network
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

# ------------------------------------------------------------
# Firewall Rules to allow GKE to access Cloud SQL privately
# ------------------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-traffic"
  network = google_compute_network.vpc_network.name
  direction = "INGRESS"
  priority = 1000
  action   = "ALLOW"

  source_ranges = ["10.0.0.0/24"]  # Allow internal network traffic within VPC

  target_tags = ["gke-node"]
}

# ------------------------------------------------------------
# Cloud SQL Proxy Setup (for secure access)
# ------------------------------------------------------------
resource "google_container_cluster" "gke_with_sql_proxy" {
  name                     = "product-gke-cluster"
  location                 = var.zone
  network                  = google_compute_network.vpc_network.name
  subnetwork               = google_compute_subnetwork.private_subnet.name
  initial_node_count       = 1
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# Set up the Kubernetes secret for Cloud SQL credentials
resource "kubernetes_secret" "cloud_sql_proxy_secret" {
  metadata {
    name      = "cloud-sql-proxy-secret"
    namespace = "default"
  }

  data = {
    "DB_HOST"     = google_sql_database_instance.postgres.private_ip
    "DB_USER"     = var.db_user
    "DB_PASSWORD" = var.db_password
  }
}

# ------------------------------------------------------------
# Deploy Cloud SQL Proxy as a Kubernetes Pod
# ------------------------------------------------------------
resource "kubernetes_deployment" "cloud_sql_proxy" {
  metadata {
    name      = "cloud-sql-proxy"
    namespace = "default"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cloud-sql-proxy"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloud-sql-proxy"
        }
      }

      spec {
        containers {
          name  = "cloud-sql-proxy"
          image = "gcr.io/cloudsql-docker/gce-proxy:1.19.1"  # Cloud SQL Proxy image

          command = [
            "/cloud_sql_proxy",
            "-dir=/cloudsql",
            "-instances=${google_sql_database_instance.postgres.connection_name}",
            "-credential_file=/secrets/cloudsql/credentials.json"
          ]

          volume_mounts {
            mount_path = "/cloudsql"
            name       = "cloudsql"
          }

          env {
            name  = "DB_HOST"
            value = google_sql_database_instance.postgres.private_ip
          }

          env {
            name  = "DB_USER"
            value = var.db_user
          }

          env {
            name  = "DB_PASSWORD"
            value = var.db_password
          }
        }

        volumes {
          name = "cloudsql"
          empty_dir {}
        }
      }
    }
  }
}

# ------------------------------------------------------------
# Kubernetes Service for API (connect with Cloud SQL Proxy)
# ------------------------------------------------------------
resource "kubernetes_service" "api_service" {
  metadata {
    name      = "product-api"
    namespace = "default"
  }

  spec {
    selector = {
      app = "product-api"
    }

    ports {
      port     = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}
