📘 Cloud-Native REST API on Google Kubernetes Engine (GKE)

This repository contains a fully containerized REST API designed for modern cloud deployment. It leverages the power of Google Kubernetes Engine (GKE) for orchestration, with all infrastructure managed as code using Terraform. The project includes a robust CI/CD pipeline built on Google Cloud Build for automated deployment.

🚀 Features

🧩 Application

REST API: Implemented using Python/Flask or Node/Express.

Configuration: Highly configurable through environment variables.

Database: Integration with Cloud SQL (PostgreSQL).

Structure: A production-ready, modular application structure.

🌐 Infrastructure

GKE Cluster: Provisioned entirely using Terraform.

Scalability: Node pools configured with autoscaling.

Database: Managed Cloud SQL PostgreSQL instance.

Networking: Secure VPC, subnets, and firewall rules.

Container Registry: Artifact Registry for secure Docker image storage.

🔄 CI/CD

Automation: An automated Cloud Build pipeline.

Workflow: Build → Test → Docker Push → Deploy to GKE.

Triggers: Configured for pushes to GitHub and manual execution.

📁 Project Structure

.
├── app/                  # Application source code
│   ├── main.py / app.js  # Main application entry point
│   ├── requirements.txt / package.json # App dependencies
│   ├── src/              # Core logic/controllers
│   └── tests/            # Unit and integration tests
│
├── Dockerfile            # Instructions to build the application container
│
├── k8s/                  # Kubernetes manifests
│   ├── deployment.yaml   # Defines the API deployment (replicas, image, etc.)
│   ├── service.yaml      # Exposes the deployment as a service (LoadBalancer/ClusterIP)
│   ├── configmap.yaml    # Non-sensitive configuration (e.g., app settings)
│   └── secret.yaml       # Sensitive configuration (e.g., database credentials)
│
├── terraform/            # Infrastructure as Code (IaC) configuration
│   ├── main.tf           # Main resource definitions
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Output values (e.g., GKE cluster name)
│   └── providers.tf      # Cloud provider configuration
│
├── cloudbuild.yaml       # Google Cloud Build pipeline definition
└── README.md             # This file


🛠️ Local Development

Prerequisites

Python (for Flask) or Node.js (for Express)

Docker

kubectl (Kubernetes CLI)

Terraform

Google Cloud SDK (gcloud)

Install Dependencies

Navigate to the app/ directory and install the necessary packages.

Python:

pip install -r requirements.txt


Node:

npm install


Run Locally

Start the application on your local machine.

Python:

python app/main.py


Node:

npm start


The API will typically be available at http://localhost:8080.

Run Tests

Ensure the application is functioning correctly before deployment.

Python (using pytest):

pytest


Node:

npm test


🐳 Docker Usage

You can build and run the application as a Docker container locally.

Build Docker Image

docker build -t app:latest .


Run Container

This command maps the container's port 8080 to your host's port 8080.

docker run -p 8080:8080 app:latest


🏗️ Terraform Infrastructure Setup

The infrastructure must be provisioned before deploying the application to GKE.

1. Configure Cloud Credentials

Ensure your gcloud CLI is authenticated and configured for the correct project.

gcloud auth application-default login
gcloud config set project [YOUR_GCP_PROJECT_ID]


2. Initialize Terraform

Navigate to the terraform/ directory to initialize the environment.

cd terraform/
terraform init


3. Validate Configuration

Check for syntax errors in your IaC.

terraform validate


4. Apply Infrastructure

Provision all necessary Google Cloud resources. Review the plan before approving!

terraform apply -auto-approve


Terraform Creates:

VPC + Subnets

GKE Cluster

Node Pools (with autoscaling)

Cloud SQL Instance (PostgreSQL)

Private Service Networking

Service Accounts + IAM Roles

Artifact Registry repository

☸️ Deploying to Kubernetes (GKE)

Once the GKE cluster is provisioned via Terraform, you can deploy the application using the Kubernetes manifests.

1. Get GKE Credentials

Configure kubectl to connect to your newly created GKE cluster.

gcloud container clusters get-credentials [CLUSTER_NAME] --region [REGION]


(The cluster name and region can be found in the Terraform outputs.)

2. Apply Kubernetes Manifests

Apply the Deployment, Service, ConfigMap, and Secret to the cluster.

kubectl apply -f k8s/


3. Check Resources

Verify that the pods are running and the service is created.

kubectl get pods
kubectl get svc


4. Get the External IP

The app-service of type LoadBalancer will receive an External IP after a few minutes, making the API accessible.

kubectl get svc app-service


🔄 CI/CD — Cloud Build Pipeline

The cloudbuild.yaml defines an automated pipeline that connects GitHub pushes directly to deployment on GKE.

Pipeline Steps

Build: Builds the Docker image from the Dockerfile.

Test: Runs the application's test suite.

Docker Push: Pushes the versioned image to Artifact Registry.

Deploy to GKE: Connects to the GKE cluster and applies the Kubernetes manifests (k8s/), initiating a new rolling deployment.

Triggered When:

Code is pushed to the main or release branches.

Manual build trigger is initiated in the Google Cloud Build console.

Configuration File

The entire CI/CD process is defined in: cloudbuild.yaml

🗄️ API Endpoints (Example)

The application exposes the following REST endpoints:

Method

Endpoint

Description

GET

/products

Returns the list of all products from Cloud SQL.

POST

/products

Adds a new product to the database.

GET

/health

Checks the service status.

Example Request (POST /products)

{
  "name": "Laptop",
  "price": 55000
}


Example Response (GET /health)

{
  "status": "ok"
}


📊 Monitoring & Logging

Monitoring and logging are enabled by default for GKE clusters:

Google Cloud Logging: Centralized collection of container logs.

Check logs: kubectl logs <pod-name>

Google Cloud Monitoring: Performance metrics for GKE, VMs, and the Load Balancer.
