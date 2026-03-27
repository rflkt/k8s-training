# Session 8 : Terraform + Cluster GKE

> **Objectifs**
> - Deployer un cluster GKE complet avec Terraform
> - Utiliser des modules Terraform (network, cluster, node_pool)
> - Comprendre les dependances entre modules
> - Se connecter au cluster et deployer une application
> - Detruire proprement l'infrastructure

> **IMPORTANT** : Pensez a executer `terraform destroy` a la fin de la session pour eviter des couts inutiles !

## Prerequis

```bash
# Verifier Terraform
terraform version

# Authentification GCP
gcloud auth application-default login
```

---

## Etape 1 : Preparer le template

Copiez le repertoire `starter/` dans votre espace de travail :

```bash
cp -r starter/ mon-cluster/
cd mon-cluster/
```

Creez votre fichier `terraform.tfvars` a partir de l'exemple :

```bash
cp terraform.tfvars.example terraform.tfvars
```

Editez `terraform.tfvars` et remplacez `votre-prenom` par votre prenom (en minuscules, sans accents) :

```hcl
project_id   = "cloud-447406"
region       = "europe-west9"
zone         = "europe-west9-a"
student_name = "hugo"
```

---

## Etape 2 : Explorer les modules

Avant de coder, explorez la structure des modules :

```
modules/
├── network/     # VPC + subnet + Cloud Router + NAT
├── cluster/     # GKE cluster (control plane)
└── node_pool/   # Node pool avec VMs spot
```

Lisez les fichiers `variables.tf` de chaque module pour comprendre les parametres attendus.

---

## Etape 3 : Completer main.tf

Ouvrez `main.tf` et decommentez les trois blocs de modules :

### 3.1 Module network

```hcl
module "network" {
  source = "./modules/network"

  network_name = "${var.student_name}-vpc"
  subnet_name  = "${var.student_name}-subnet"
  subnet_cidr  = "10.10.0.0/24"
  region       = var.region
}
```

Ce module cree :
- Un VPC dedie
- Un sous-reseau avec acces prive Google
- Un Cloud Router + NAT pour l'acces internet des noeuds

### 3.2 Module cluster

```hcl
module "cluster" {
  source = "./modules/cluster"

  cluster_name = "${var.student_name}-cluster"
  location     = var.zone
  project_id   = var.project_id
  network      = module.network.network_name
  subnetwork   = module.network.subnet_name
}
```

Notez la **dependance** : le cluster utilise les outputs du module network (`module.network.network_name`). Terraform comprend automatiquement l'ordre de creation.

### 3.3 Module node_pool

```hcl
module "node_pool" {
  source = "./modules/node_pool"

  pool_name    = "${var.student_name}-pool"
  location     = var.zone
  cluster_id   = module.cluster.cluster_id
  machine_type = "e2-medium"
  node_count   = 1
  spot         = true
}
```

Les VMs **spot** coutent ~60-91% moins cher que les VMs standard. Parfait pour un environnement de formation.

### 3.4 Completer outputs.tf

Decommentez les outputs dans `outputs.tf` pour afficher l'endpoint du cluster et la commande kubeconfig.

---

## Etape 4 : Init / Plan / Apply

### 4.1 Initialiser

```bash
terraform init
```

Terraform telecharge le provider Google et prepare les modules.

### 4.2 Planifier

```bash
terraform plan
```

Verifiez le plan : vous devriez voir environ **6-7 ressources** a creer (VPC, subnet, router, NAT, cluster, node pool).

### 4.3 Appliquer

```bash
terraform apply
```

Tapez `yes`. La creation prend environ **5 a 8 minutes** (le cluster GKE est la ressource la plus longue).

---

## Etape 5 : Se connecter au cluster

Utilisez la commande affichee dans les outputs :

```bash
# Copier la commande depuis l'output "kubeconfig_command"
gcloud container clusters get-credentials <VOTRE_PRENOM>-cluster \
  --zone europe-west9-a \
  --project cloud-447406
```

Verifiez la connexion :

```bash
kubectl get nodes
kubectl cluster-info
```

---

## Etape 6 : Deployer une application

Creez le namespace et deployez l'API :

```bash
kubectl create namespace exercices

kubectl create deployment api \
  --image=europe-west9-docker.pkg.dev/cloud-447406/training/api:v1 \
  --namespace=exercices

kubectl expose deployment api \
  --port=80 --target-port=8080 \
  --namespace=exercices

kubectl get pods -n exercices
```

Votre cluster Terraform fonctionne et heberge une application.

---

## Etape 7 : Detruire l'infrastructure

> **OBLIGATOIRE** : Detruisez votre cluster a la fin de la session pour eviter les couts !

```bash
# Supprimer les ressources K8s d'abord (evite les blocages)
kubectl delete namespace exercices --ignore-not-found

# Detruire toute l'infrastructure Terraform
terraform destroy
```

Tapez `yes`. La destruction prend environ 5 minutes.

Verifiez dans la console GCP que toutes les ressources ont ete supprimees.

---

## Recapitulatif

| Ressource | Module | Temps de creation |
|-----------|--------|-------------------|
| VPC + subnet | network | ~30s |
| Cloud Router + NAT | network | ~1min |
| Cluster GKE | cluster | ~5-7min |
| Node pool | node_pool | ~2-3min |

---

## Nettoyage

```bash
terraform destroy
```

---

## Mini-defi

Ajoutez **Traefik** comme ingress controller en utilisant le provider Helm de Terraform. Ajoutez ceci a votre `main.tf` :

```hcl
provider "helm" {
  kubernetes {
    host                   = "https://${module.cluster.cluster_endpoint}"
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}

data "google_client_config" "default" {}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  namespace  = "traefik"
  create_namespace = true
}
```

> **Indice** : vous devrez aussi ajouter un output `cluster_ca_certificate` dans le module cluster.
