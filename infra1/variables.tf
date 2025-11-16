variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "network" {
  type    = string
  default = "default"
}

variable "subnetwork" {
  type    = string
  default = "default"
}

variable "authorized_cidr" {
  type    = string
  default = " 45.118.72.227/32" # << MUST change to your IP/CIDR in production (e.g. "203.0.113.4/32")
}

variable "node_machine_type" {
  type    = string
  default = "e2-small"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "db_tier" {
  type    = string
  default = "db-f1-micro"
}

variable "db_name" {
  type    = string
  default = "productdb"
}

variable "db_user" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}
