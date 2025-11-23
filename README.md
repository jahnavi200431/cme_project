# Scalable REST API Deployment on Google Kubernetes Engine (GKE)

_A Cloud-Native Application with Terraform IaC, Cloud SQL, Kubernetes, and CI/CD Automation_

---

## 1. Executive Summary

This project delivers a fully operational, cloud-native REST API deployed on Google Kubernetes Engine (GKE), integrated with a PostgreSQL backend hosted on Cloud SQL. The solution is packaged using Docker, orchestrated with Kubernetes, and fully automated through a Continuous Integration/Continuous Deployment (CI/CD) pipeline powered by Google Cloud Build.


---

## 2. Key Capabilities

### 2.1 Application Layer

- REST API implemented using Python (Flask) 
- CRUD operations for Product entity
- Structured JSON-based logging


### 2.2 Infrastructure Layer

- GKE cluster deployment using Terraform
- Managed PostgreSQL database using Cloud SQL 
- IAM roles defined through IaC
- Kubernetes resources include:
  - Deployments
  - Services
  - Horizontal Pod Autoscaler (HPA)
 

### 2.3 CI/CD Layer

- Automated CI/CD via Cloud Build
- Continuous delivery through rolling updates on GKE
- Container image storage in Artifact Registry
- Integration and health checks executed post-deployment

### 2.4 Operational Excellence

- Centralized logging through Cloud Logging
- Metrics dashboard and alerting through Cloud Monitoring
- Secure communication and controlled access using IAM, Secrets

---


## 3. Repository Structure

```
.
├── app/                   
│   ├── app.py
│   ├── requirements.txt 
│   ├── Dockerfile
|   |__start.sh
|
├── k8s/                  
│   ├── deployment.yaml
│   ├── ServiceAccount.yaml
|
|
├── infra/            
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│
├── tests/
│   └── integration_tests.sh
│
|___cloudbuild.yaml                
└── README.md            
```

---

## 4. API Specifications

### Product Endpoints

| Method | Endpoint          | Description                |
| ------ | ---------------- | ------------------------- |
| GET    | /products        | Retrieve all products     |
| GET    | /products/{id}   | Retrieve product by ID    |
| POST   | /products        | Create new product        |
| PUT    | /products/{id}   | Update existing product   |
| DELETE | /products/{id}   | Delete product            |

### Health Monitoring

- **GET /health** → Returns application uptime status

---

## 5. Database Schema

| Field        | Type         | Description         |
| ------------ | ------------ | -------------------|
| id           | UUID / INT   | Primary key         |
| name         | VARCHAR(255) | Product name        |
| description  | TEXT         | Product description |
| price        | DECIMAL/FLOAT| Product price       |
| quantity     | INTEGER      | Available stock     |
| created_at   | TIMESTAMP    | Auto-generated      |
| updated_at   | TIMESTAMP    | Auto-updated        |

---

## 6. Deployment Workflow

### 6.1 Local Execution

_Install dependencies:_
```bash
pip install -r requirements.txt
```

_Run application:_
```bash
python app/app.py
```

### 6.2 Docker Build
```bash
docker build -t product-api .
docker run -p 8080:8080 product-api
```

### 6.3 Kubernetes Deployment
```bash
kubectl apply -f k8s/
kubectl get pods
kubectl get svc
```

### 6.4 Terraform Infrastructure Deployment
```bash
cd terraform/
terraform init
terraform apply -auto-approve
```

---

## 7. CI/CD Pipeline Overview

The CI/CD pipeline automates the complete delivery workflow:

**Build Stage**
- Docker image creation
- Tagging using commit SHA
- Push to Artifact Registry

**Deployment Stage**
- Trigger rolling update in GKE
- Update Kubernetes Deployment manifest

**Post-Deployment Validation**
- Integration tests
- Health checks
- Automated endpoint verification

---

## 8. Security Framework

- IAM least-privilege for GKE, Cloud Build, SQL access
- Kubernetes Secrets for DB Password
- API-level authentication via API key 


---

## 9. Monitoring & Observability

**Logging**
- Application logs forwarded to Cloud Logging
 

**Monitoring**
- Metrics tracked:
  - Request latency
  - Error rate
  - CPU & memory usage
- Custom dashboards and alert policies configured in Cloud Monitoring

---

## 10. Troubleshooting Guide

| Issue             | Description                       | Resolution                           |
| ----------------- | --------------------------------- | ------------------------------------- |
| CrashLoopBackOff  | App failing to start              | Validate Secrets/ConfigMaps           |
| SQL Connection Error | Incorrect networking or credentials | Ensure Private IP + cloud proxy running |
| ImagePullError    | GKE unable to fetch container     | Grant Artifact Registry permissions   |
| No External IP    | Service misconfiguration          | Set Service type to LoadBalancer      |


---
