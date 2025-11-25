

variable "project_id" {
  description = "The Google Cloud project ID"
  default = "my-project-app-477009"
}


variable "region_name" {
  description = "The region where resources will be created"
  default     = "us-central1"
}

variable "zone_name" {
  description = "The zone for resources"
  default     = "us-central1-a"
}

variable "vpc_name" {
  description = "The name of the VPC"
  default     = "products-vpc1"
}

variable "subnet_name" {
  description = "The name of the subnet"
  default     = "products-subnet1"
}

variable "cluster_name" {
  description = "The name of the subnet"
  default     = "products-gke-cluster1"
}
variable "db_instance_name" {
  description = "The name of the PostgreSQL database"
  default     = "products-db-instance1"
}
variable "firewall_name" {
  description = "The name of the PostgreSQL database"
  default     = "allow-internal-traffic1"
}
variable "db_name" {
  description = "The name of the PostgreSQL database"
  default     = "appdb"
}

variable "db_user" {
  description = "The username for the PostgreSQL database"
  default     = "user1"
}

variable "db_password" {
  description = "The database password"
   default     = "test"
}

