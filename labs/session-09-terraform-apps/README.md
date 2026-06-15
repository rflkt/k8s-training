# Session 9 : Terraform Apps & Helm

## Objectifs

- Creer un **module Terraform reutilisable** pour deployer des applications Kubernetes
- Deployer l'API et le frontend via le meme module
- Installer **Traefik** (ingress controller) via le **provider Helm** de Terraform
- Exposer le frontend via un **Ingress** natif et le joindre depuis l'exterieur
- (Optionnel) Integrer la gestion des secrets GCP via le **CSI driver**

## Pre-requis

- Terraform installe (`terraform version`)
- Un acces a un cluster GKE :
  - **Cluster partage (le cas de la classe)** — fourni par le formateur. Vous
    recevez un **namespace dedie** (`trainee-NN`) et un **kubeconfig de trainee**.
    Traefik est **deja installe** par le formateur ; vous n'avez qu'un acces
    `edit` sur votre namespace (vous ne pouvez pas creer de ressources
    *cluster-scoped* : namespaces, ClusterRoles, IngressClass, CRDs...).
  - **Votre propre cluster** — recree comme en Session 8 (`terraform apply`),
    ou vous etes administrateur.

### Sur le cluster partage (le cas de la classe)

1. Recuperez le kubeconfig de trainee genere par le formateur (cote
   `cloud-infrastructure` : `make training-export-kubeconfig`). Copiez
   `training-kubeconfig.yaml` a cote de votre `main.tf`.
2. Creez `terraform.tfvars` (voir [`terraform.tfvars.example`](solution/terraform.tfvars.example)) :

   ```hcl
   kubeconfig       = "./training-kubeconfig.yaml"
   namespace        = "trainee-01"   # VOTRE namespace assigne
   create_namespace = false          # le formateur l'a deja cree
   install_traefik  = false          # le formateur a deja installe Traefik
   ```

> Sur **votre propre cluster** (admin) : `create_namespace = true`,
> `install_traefik = true`, `kubeconfig = "~/.kube/config"`.

> Le **CSI driver** (`secrets-store`) n'est necessaire que pour l'etape 6 (optionnelle).

---

## Etape 1 : Creer le module applicatif

Ouvrez `starter/modules/app/main.tf`. Ce fichier contient un squelette avec des TODOs.

Le module doit creer :
- Un **Deployment** Kubernetes avec l'image et les replicas specifies
- Un **Service** ClusterIP pour exposer le Deployment
- (Optionnel) un **Ingress** natif (`kubernetes_ingress_v1`) si `enable_ingress = true`

> **Pourquoi un Ingress natif et pas une IngressRoute Traefik ?**
> `kubernetes_manifest` resout le CRD **au moment du `plan`** : utiliser une
> `IngressRoute` (CRD Traefik) ferait **echouer `terraform plan`** tant que Traefik
> n'est pas installe. Un `kubernetes_ingress_v1` (API native, toujours presente)
> se plannifie toujours, et Traefik le prend en charge via `ingress_class_name`.

Completez les TODOs un par un.

## Etape 2 : Definir les variables du module

Ouvrez `starter/modules/app/variables.tf`. Definissez : `app_name`, `namespace`,
`image`, `replicas` (defaut 1), `port` (defaut 8080), `env_vars` (map, defaut `{}`),
`enable_ingress` (bool, defaut `false`), `host` (string, defaut `""`).

## Etape 3 : Installer Traefik via Helm

Dans `starter/main.tf`, ajoutez un `helm_release` pour installer Traefik (c'est la
partie **Helm** de la session : Terraform pilote un release Helm) :

```hcl
resource "helm_release" "traefik" {
  count = var.install_traefik ? 1 : 0

  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "27.0.0"
  namespace        = "traefik"
  create_namespace = true
}
```

> **Cluster partage :** laissez `install_traefik = false`. Installer Traefik cree
> des ressources *cluster-scoped* (namespace, ClusterRole, IngressClass, CRDs) que
> votre acces `edit` ne permet **pas** — et de toute facon le formateur l'a deja
> installe une seule fois pour toute la classe. Le `count` ci-dessus rend donc le
> bloc inactif chez vous. Sur votre propre cluster (admin), mettez `install_traefik = true`.

## Etape 4 : Deployer l'API

```hcl
module "api" {
  source     = "./modules/app"
  app_name   = "api"
  namespace  = var.namespace
  image      = "europe-west9-docker.pkg.dev/cloud-447406/training/api:v1"
  port       = 8080
  env_vars   = { ENVIRONMENT = "training" }
  depends_on = [kubernetes_namespace.exercices]
}
```

## Etape 5 : Deployer le frontend avec le meme module

```hcl
module "frontend" {
  source         = "./modules/app"
  app_name       = "frontend"
  namespace      = var.namespace
  image          = "europe-west9-docker.pkg.dev/cloud-447406/training/frontend:v1"
  port           = 80
  enable_ingress = true
  host           = "frontend.training.local"

  # Le frontend (nginx) proxy /api/ vers le Service api. Comme le Service api
  # ecoute sur le port 80 dans le cluster, on le lui indique via API_URL.
  env_vars = {
    API_URL = "http://api.${var.namespace}.svc.cluster.local:80"
  }

  depends_on = [kubernetes_namespace.exercices, helm_release.traefik]
}
```

## Etape 6 (optionnelle, avancee) : SecretProviderClass via le CSI driver

Cette etape monte un secret GCP Secret Manager dans les pods via le **secrets-store
CSI driver**. Elle est **gardee par `var.enable_secret_csi`** (defaut `false`) car
`kubernetes_manifest` resout le CRD `SecretProviderClass` **au plan** : si le CSI
driver n'est pas installe, activer cette etape fait echouer `terraform plan`.

Pre-requis pour cette etape : le secrets-store CSI driver installe sur le cluster, par ex.

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system
# + le provider GCP du CSI driver
```

Puis activez l'etape :

```bash
terraform apply -var enable_secret_csi=true
```

## Etape 7 : Appliquer

```bash
terraform init
terraform plan
terraform apply
```

Verifiez les ressources :

```bash
NS=trainee-01   # VOTRE namespace
kubectl get deployments -n $NS
kubectl get services -n $NS
kubectl get ingress -n $NS
kubectl get pods -n $NS
```

Recuperez l'IP publique de Traefik et joignez le frontend. L'Ingress route sur
`Host=frontend.<namespace>.training.local` (le host inclut votre namespace pour
eviter les collisions entre stagiaires) :

```bash
kubectl get svc traefik -n traefik   # attendez l'EXTERNAL-IP

EXTERNAL_IP=$(kubectl get svc traefik -n traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Remplacez trainee-01 par VOTRE namespace
curl -H "Host: frontend.trainee-01.training.local" http://$EXTERNAL_IP/
```

## Nettoyage

```bash
# Supprime les apps + le release Helm Traefik gere par Terraform
terraform destroy
```

> Si vous etes sur un cluster partage, ne detruisez que **votre** namespace /
> vos ressources — pas le cluster des autres.

---

## Bonus

Voir [exercices bonus](./bonus/README.md) : blocs dynamiques (volumes optionnels),
`for_each` multi-apps, workspaces, et secrets sensibles.
