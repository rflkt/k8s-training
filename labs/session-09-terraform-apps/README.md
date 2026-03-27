# Session 9 : Terraform Apps & Helm

## Objectifs

- Creer un **module Terraform reutilisable** pour deployer des applications Kubernetes
- Deployer l'API et le frontend via le meme module
- Comprendre la parametrisation des modules (variables, outputs)
- Integrer la gestion des secrets CSI dans Terraform

## Pre-requis

- Terraform installe (`terraform version`)
- `kubectl` configure vers votre cluster
- Namespace `exercices` existant

## Etapes

### 1. Creer le module applicatif

Ouvrez `starter/modules/app/main.tf`. Ce fichier contient un squelette avec des TODOs.

Le module doit creer :
- Un **Deployment** Kubernetes avec l'image et les replicas specifies
- Un **Service** ClusterIP pour exposer le Deployment
- (Optionnel) Une **IngressRoute** Traefik si `enable_ingress = true`

Completez les TODOs un par un.

### 2. Definir les variables du module

Ouvrez `starter/modules/app/variables.tf`. Definissez les variables suivantes :
- `app_name` : nom de l'application
- `namespace` : namespace Kubernetes
- `image` : image Docker a deployer
- `replicas` : nombre de replicas (defaut: 1)
- `port` : port du conteneur (defaut: 8080)
- `env_vars` : map de variables d'environnement
- `enable_ingress` : activer l'IngressRoute (defaut: false)
- `host` : hostname pour l'IngressRoute

### 3. Deployer l'API

Dans `starter/main.tf`, utilisez le module pour deployer l'API :
```hcl
module "api" {
  source    = "./modules/app"
  app_name  = "api"
  namespace = "exercices"
  image     = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
  port      = 8080
  env_vars  = {
    ENVIRONMENT = "training"
  }
}
```

### 4. Deployer le frontend avec le meme module

Ajoutez un second appel au module pour le frontend :
```hcl
module "frontend" {
  source         = "./modules/app"
  app_name       = "frontend"
  namespace      = "exercices"
  image          = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
  port           = 80
  enable_ingress = true
  host           = "frontend.training.local"
}
```

### 5. Ajouter une SecretProviderClass dans Terraform

Ajoutez une ressource `kubernetes_manifest` dans `main.tf` pour creer une `SecretProviderClass` qui monte les secrets GCP dans les pods.

### 6. Appliquer

```bash
terraform init
terraform plan
terraform apply
```

Verifiez :
```bash
kubectl get deployments -n exercices
kubectl get services -n exercices
kubectl get pods -n exercices
```

## Bonus

- Ajoutez une variable `environment` au module (ex: `staging`, `production`) et utilisez-la pour prefixer les noms de ressources : `${var.environment}-${var.app_name}`
- Ajoutez des outputs au module (nom du service, URL interne)
- Creez un fichier `terraform.tfvars` pour externaliser les valeurs

## Mini-defi

Modifiez le module pour supporter un volume `emptyDir` optionnel monte sur `/tmp/cache`. Ajoutez une variable `enable_cache_volume` (defaut: `false`) et conditionnez la creation du volume avec `dynamic "volume"`.

Verifiez que l'API fonctionne toujours apres le changement :
```bash
kubectl exec -n exercices deploy/api -- ls /tmp/cache
```
