project_id  = "my-project-app-477009"
region      = "us-central1"
zone        = "us-central1-a"

db_user     = "postgres"
db_password = "postgres"

# IMPORTANT: replace with the smallest possible CIDR covering only trusted IP(s)
authorized_cidr = "45.118.72.227/32"   # <-- change this to your office / Cloud Build IP
