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
  subnet_cidr  = "10.0.1.0/24"
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

  pool_name      = "${var.student_name}-pool"
  location       = var.zone
  cluster_id     = module.cluster.cluster_id
  machine_type   = "e2-small"
  node_count     = 1
  min_node_count = 1
  max_node_count = 3
  spot           = true
}
```

Les VMs **spot** coutent ~60-91% moins cher que les VMs standard. Parfait pour un environnement de formation. Le node pool est **autoscale** : il demarre a 1 noeud et peut monter jusqu'a 3 selon la charge.

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

Tapez `yes`. La creation prend environ **8 a 12 minutes** (le cluster GKE est la ressource la plus longue : comptez ~10 min rien que pour le control plane).

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

## Etape 7 : Exposer l'API via Traefik (IP publique)

Pour l'instant l'API n'est joignable qu'a l'interieur du cluster. Installons **Traefik**
comme ingress controller pour l'exposer sur une **IP publique** et l'appeler depuis votre machine.

### 7.1 Installer Traefik avec Helm

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace traefik --create-namespace
```

Traefik cree un Service de type `LoadBalancer`. GKE provisionne une IP publique (1-2 min).

### 7.2 Recuperer l'IP publique

```bash
# Attendez que la colonne EXTERNAL-IP passe de <pending> a une vraie IP
kubectl get svc traefik -n traefik
```

### 7.3 Creer un Ingress vers l'API

Creez un fichier `ingress.yaml` :

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  namespace: exercices
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port:
                  number: 80
```

```bash
kubectl apply -f ingress.yaml
```

### 7.4 Appeler l'API depuis votre machine

```bash
EXTERNAL_IP=$(kubectl get svc traefik -n traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl http://$EXTERNAL_IP/health
curl http://$EXTERNAL_IP/info
```

Vous obtenez une reponse de l'API qui tourne dans **votre** cluster Terraform, depuis Internet.

> **Piege important** : Traefik et son LoadBalancer sont crees avec `helm`/`kubectl`, **pas**
> avec Terraform. Le `terraform destroy` ne les connait donc pas (ils ne sont pas dans le state).
> Il faut les supprimer **avant** de detruire le cluster (etape suivante), sinon le Load Balancer
> GCP reste actif et continue de facturer.

---

## Etape 8 : Detruire l'infrastructure

> **OBLIGATOIRE** : Detruisez votre cluster a la fin de la session pour eviter les couts !

```bash
# 1. Supprimer ce qui a ete cree HORS Terraform (Traefik + son LoadBalancer)
helm uninstall traefik -n traefik
kubectl delete namespace traefik --ignore-not-found

# 2. Supprimer les ressources applicatives
kubectl delete namespace exercices --ignore-not-found

# 3. Detruire toute l'infrastructure Terraform
terraform destroy
```

Tapez `yes`. La destruction prend environ 5 minutes.

Verifiez dans la console GCP que toutes les ressources ont ete supprimees (cluster, reseau,
**et** le Load Balancer de Traefik).

---

## Recapitulatif

| Ressource | Module | Temps de creation |
|-----------|--------|-------------------|
| VPC + subnet | network | ~30s |
| Cloud Router + NAT | network | ~1min |
| Cluster GKE | cluster | ~8-10min |
| Node pool | node_pool | ~2-3min |

---

## Nettoyage

```bash
terraform destroy
```

---

## Pour aller plus loin (preview Session 9)

A l'etape 7 vous avez installe Traefik avec le CLI `helm`. En **Session 9**, on fera la meme
chose **en Infrastructure-as-Code** : piloter Helm depuis Terraform (`helm_release`) pour que
l'ingress controller soit cree et detruit avec le reste de l'infra — fini le `helm`/`kubectl`
manuel hors du state.

Apercu du futur module :

```hcl
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  namespace        = "traefik"
  create_namespace = true
}
```

> Ainsi le `terraform destroy` supprimera **aussi** Traefik et son Load Balancer — plus de
> ressources orphelines qui facturent. On verra ca en detail Session 9.

Pour ceux qui ont fini en avance : voir les [exercices bonus](./bonus/README.md).
