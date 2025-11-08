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
variable "gke_cluster_name" {
  type    = string
  default = "product-gke-cluster"
}
variable "db_instance_name" {
  type    = string
  default = "product-db-instance"
}
variable "db_name" {
  type    = string
  default = "productdb"
}
variable "db_user" {
  type    = string
  default = "postgres"
}
variable "db_password" {
  type      = string
  sensitive = true
}
variable "artifact_repo_name" {
  type    = string
  default = "product-repo"
}
