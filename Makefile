NS           ?= exercices
CLUSTER      ?= training
API_VERSION  ?= v1

# --- kubectl get ---

get-pods: ## kubectl get pods
	kubectl get pods -n $(NS) -o wide

get-svc: ## kubectl get services
	kubectl get svc -n $(NS)

get-deploy: ## kubectl get deployments
	kubectl get deployments -n $(NS)

get-all: ## kubectl get all
	kubectl get all -n $(NS)

# --- kubectl apply/delete ---

apply: ## Appliquer un manifeste (FILE=xxx.yaml)
	kubectl apply -f $(FILE) -n $(NS)

delete: ## Supprimer un manifeste (FILE=xxx.yaml)
	kubectl delete -f $(FILE) -n $(NS)

# --- Debug ---

logs: ## Logs d'un pod (POD=xxx)
	kubectl logs -f $(POD) -n $(NS)

describe: ## Describe d'un pod (POD=xxx)
	kubectl describe pod $(POD) -n $(NS)

exec: ## Shell dans un pod (POD=xxx)
	kubectl exec -it $(POD) -n $(NS) -- /bin/sh

# --- Build & load images ---

build-api: ## Build image API
	docker build -t api:$(API_VERSION) --build-arg VERSION=$(API_VERSION) app/api/

build-frontend: ## Build image frontend
	docker build -t frontend:v1 app/frontend/

load-api: ## Charger image API dans kind
	kind load docker-image api:$(API_VERSION) --name $(CLUSTER)

load-frontend: ## Charger image frontend dans kind
	kind load docker-image frontend:v1 --name $(CLUSTER)

# --- Help ---

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
.PHONY: get-pods get-svc get-deploy get-all apply delete logs describe exec build-api build-frontend load-api load-frontend help
