# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

22-hour practical Kubernetes training course (11 sessions x 2h) for backend/full-stack developers. All course materials are written in **French**. Uses a thread application (Go API + React/nginx frontend) deployed on a local kind cluster, progressing from K8s fundamentals to production CI/CD.

## Common Commands

### Local Environment Setup
```bash
./setup/prerequisites.sh          # Install all tools (Docker, kubectl, kind, Helm, Terraform, gcloud)
./setup/verify-setup.sh           # Verify all tools are installed with correct versions
kind create cluster --config setup/kind-config.yaml --name training   # Create 3-node kind cluster
kind delete cluster --name training
```

### Building the Application
```bash
# API (Go) - standard build
docker build -t api:v1 --build-arg VERSION=v1 app/api/
# API - optimized scratch-based image
docker build -t api:v1 --build-arg VERSION=v1 -f app/api/Dockerfile.multistage app/api/
# Frontend (nginx)
docker build -t frontend:v1 app/frontend/
# Load images into kind cluster
kind load docker-image api:v1 --name training
kind load docker-image frontend:v1 --name training
```

### Running Locally with Docker Compose
```bash
cd app && docker-compose up -d    # Starts api, frontend, postgres
cd app && docker-compose down
```

### Terraform (sessions 7-9)
```bash
cd terraform/student-template
cp terraform.tfvars.example terraform.tfvars  # Edit with your values
terraform init
terraform plan
terraform apply
terraform destroy
```

## Architecture

### Application (`app/`)
- **`api/`** - Go 1.22 REST API (port 8080). Single `main.go` with CRUD endpoints (`/items`), health/readiness probes (`/health`, `/ready`), info endpoint (`/info`), and secret test endpoint (`/secret-test`). Version is injected at build time via `-ldflags`. Connects to PostgreSQL with automatic retry logic.
- **`frontend/`** - Static HTML/JS served by nginx:1.25-alpine (port 80). nginx proxies `/api/` requests to the backend. Auto-refreshes API status every 5s to demonstrate pod rotation.
- **`docker-compose.yml`** - 3-service stack: api, frontend, postgres (16-alpine).

### Labs (`labs/`)
Each session has `starter/` (incomplete YAMLs with TODOs) and `solution/` (working manifests). Sessions 1-6 cover K8s concepts (pods, services, ingress, storage, secrets), 7-9 cover Terraform (intro, GKE cluster, app deployment), 10 covers production patterns (HPA, probes, resource limits), 11 covers CI/CD (GitHub Actions deploying to GKE).

### Terraform (`terraform/student-template/`)
Multi-module GKE provisioning: `modules/network/` (VPC, subnet, Cloud NAT), `modules/cluster/` (GKE control plane), `modules/node_pool/` (e2-small spot VMs with autoscaling). Resources are prefixed with student name variable.

### CI/CD (`labs/session-11-cicd/`)
GitHub Actions workflow: build with `Dockerfile.multistage`, push to Google Artifact Registry (`europe-west9-docker.pkg.dev`), deploy via `kubectl set image` with Workload Identity Federation auth.

## Key Patterns
- Docker images use `imagePullPolicy: Never` when loaded into kind via `kind load docker-image`
- The API version (v1/v2) is set at Docker build time with `--build-arg VERSION=v1`, compiled into the binary via Go ldflags
- Lab exercises use the `exercises` namespace consistently
- Terraform modules use `var.student_name` prefix for all GCP resource names to avoid collisions
