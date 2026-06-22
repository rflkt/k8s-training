# Session 9 : Terraform Apps & Helm

## Objectifs

- Créer un **module Terraform réutilisable** pour déployer des applications Kubernetes
- Déployer l'API et le frontend via le même module
- Installer **Traefik** (ingress controller) via le **provider Helm** de Terraform
- Exposer le frontend via un **Ingress** natif et le joindre depuis l'extérieur
- (Optionnel) Intégrer la gestion des secrets GCP via le **CSI driver**

## Pré-requis

- Terraform installé (`terraform version`)
- Un accès à un cluster GKE :
  - **Cluster partagé (le cas de la classe)** — fourni par le formateur. Vous
    recevez un **namespace dédié** (`trainee-NN`) et un **kubeconfig de trainee**.
    Traefik est **déjà installé** par le formateur ; vous n'avez qu'un accès
    `edit` sur votre namespace (vous ne pouvez pas créer de ressources
    *cluster-scoped* : namespaces, ClusterRoles, IngressClass, CRDs...).
  - **Votre propre cluster** — recréé comme en Session 8 (`terraform apply`),
    où vous êtes administrateur.

### Sur le cluster partagé (le cas de la classe)

1. Récupérez le kubeconfig de trainee généré par le formateur (côté
   `cloud-infrastructure` : `make training-export-kubeconfig`). Copiez
   `training-kubeconfig.yaml` à côté de votre `main.tf`.
2. Créez `terraform.tfvars` (voir [`terraform.tfvars.example`](solution/terraform.tfvars.example)) :

   ```hcl
   kubeconfig       = "./training-kubeconfig.yaml"
   namespace        = "trainee-01"   # VOTRE namespace assigné
   create_namespace = false          # le formateur l'a déjà créé
   install_traefik  = false          # le formateur a déjà installé Traefik
   ```

> Sur **votre propre cluster** (admin) : `create_namespace = true`,
> `install_traefik = true`, `kubeconfig = "~/.kube/config"`.

> Le **CSI driver** (`secrets-store`) n'est nécessaire que pour l'étape 6 (optionnelle).

---

## Étape 1 : Créer le module applicatif

Ouvrez `starter/modules/app/main.tf`. Ce fichier contient un squelette avec des TODOs.

Le module doit créer :
- Un **Deployment** Kubernetes avec l'image et les replicas spécifiés
- Un **Service** ClusterIP pour exposer le Deployment
- (Optionnel) un **Ingress** natif (`kubernetes_ingress_v1`) si `enable_ingress = true`

> **Pourquoi un Ingress natif et pas une IngressRoute Traefik ?**
> `kubernetes_manifest` résout le CRD **au moment du `plan`** : utiliser une
> `IngressRoute` (CRD Traefik) ferait **échouer `terraform plan`** tant que Traefik
> n'est pas installé. Un `kubernetes_ingress_v1` (API native, toujours présente)
> se planifie toujours, et Traefik le prend en charge via `ingress_class_name`.

Complétez les TODOs un par un.

## Étape 2 : Définir les variables du module

Ouvrez `starter/modules/app/variables.tf`. Définissez : `app_name`, `namespace`,
`image`, `replicas` (défaut 1), `port` (défaut 8080), `env_vars` (map, défaut `{}`),
`enable_ingress` (bool, défaut `false`), `host` (string, défaut `""`).

## Étape 3 : Installer Traefik via Helm

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

> **Cluster partagé :** laissez `install_traefik = false`. Installer Traefik crée
> des ressources *cluster-scoped* (namespace, ClusterRole, IngressClass, CRDs) que
> votre accès `edit` ne permet **pas** — et de toute façon le formateur l'a déjà
> installé une seule fois pour toute la classe. Le `count` ci-dessus rend donc le
> bloc inactif chez vous. Sur votre propre cluster (admin), mettez `install_traefik = true`.

## Étape 4 : Déployer l'API

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

## Étape 5 : Déployer le frontend avec le même module

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

## Étape 6 (optionnelle, avancée) : SecretProviderClass via le CSI driver

Cette étape monte un secret GCP Secret Manager dans les pods via le **secrets-store
CSI driver**. Elle est **gardée par `var.enable_secret_csi`** (défaut `false`) car
`kubernetes_manifest` résout le CRD `SecretProviderClass` **au plan** : si le CSI
driver n'est pas installé, activer cette étape fait échouer `terraform plan`.

Pré-requis pour cette étape : le secrets-store CSI driver installé sur le cluster, par ex.

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system
# + le provider GCP du CSI driver
```

Puis activez l'étape :

```bash
terraform apply -var enable_secret_csi=true
```

## Étape 7 : Appliquer

```bash
terraform init
terraform plan
terraform apply
```

Vérifiez les ressources :

```bash
NS=trainee-01   # VOTRE namespace
kubectl get deployments -n $NS
kubectl get services -n $NS
kubectl get ingress -n $NS
kubectl get pods -n $NS
```

Récupérez l'IP publique de Traefik et joignez le frontend. L'Ingress route sur
`Host=frontend.<namespace>.training.local` (le host inclut votre namespace pour
éviter les collisions entre stagiaires) :

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

> Si vous êtes sur un cluster partagé, ne détruisez que **votre** namespace /
> vos ressources — pas le cluster des autres.

---

## Bonus

Voir [exercices bonus](./bonus/README.md) : blocs dynamiques (volumes optionnels),
`for_each` multi-apps, workspaces, et secrets sensibles.
