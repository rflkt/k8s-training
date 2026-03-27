# Formation Kubernetes -- 22h (11 sessions)

Formation pratique Kubernetes destinee aux developpeurs backend et fullstack. De la decouverte des concepts fondamentaux jusqu'au deploiement en production avec CI/CD, en passant par Terraform et Helm.

Chaque session de 2h combine theorie (~45 min) et lab pratique (~1h15) sur un cluster local [kind](https://kind.sigs.k8s.io/). Les labs utilisent une application fil rouge composee d'une API Go et d'un frontend React.

---

## Planning

| # | Session | Sujets | Lab |
|---|---------|--------|-----|
| 01 | Fondamentaux K8s | Pods, ReplicaSets, Deployments, namespaces, labels, kubectl | [lab](labs/session-01-fundamentals/) |
| 02 | Services & Networking | ClusterIP, NodePort, LoadBalancer, DNS interne, endpoints | [lab](labs/session-02-services/) |
| 03 | Ingress | Ingress controllers, Traefik, regles de routage, TLS | [lab](labs/session-03-ingress/) |
| 04 | Storage | Volumes, PV, PVC, StorageClass, ConfigMaps comme volumes | [lab](labs/session-04-storage/) |
| 05 | Secrets (bases) | Secrets K8s, types, montage en volume et env vars, encoding | [lab](labs/session-05-secrets-basics/) |
| 06 | Secrets (avance) | External Secrets Operator, GCP Secret Manager, CSI driver, rotation | [lab](labs/session-06-secrets-advanced/) |
| 07 | Terraform (intro) | HCL, providers, resources, state, plan/apply, modules | [lab](labs/session-07-terraform-intro/) |
| 08 | Terraform (cluster) | Provisionner un cluster GKE, VPC, subnets, IAM, node pools | [lab](labs/session-08-terraform-cluster/) |
| 09 | Terraform (apps) | Deployer des apps K8s via Terraform, Helm provider, variables | [lab](labs/session-09-terraform-apps/) |
| 10 | Production | Health checks, resource limits, HPA, rolling updates, observabilite | [lab](labs/session-10-production/) |
| 11 | CI/CD | GitHub Actions, build/push images, deploy on push, environments | [lab](labs/session-11-cicd/) |

---

## Prerequis

| Outil | Version min. | Obligatoire |
|-------|-------------|-------------|
| Docker Desktop / Rancher Desktop | latest | oui |
| kubectl | >= 1.28 | oui |
| kind | >= 0.20 | oui |
| Helm | >= 3.13 | oui |
| Terraform | >= 1.13 | oui |
| gcloud CLI | latest | oui |
| VS Code | latest | recommande |
| Git | >= 2.40 | oui |

Extensions VS Code recommandees : Kubernetes, YAML, HashiCorp Terraform, Go.

Voir [SETUP.md](SETUP.md) pour les instructions d'installation detaillees par OS.

---

## Demarrage rapide

```bash
# 1. Cloner le repo
git clone https://github.com/rflkt/k8s-training.git
cd k8s-training

# 2. Installer les prerequis (Mac/Linux)
./setup/prerequisites.sh

# 3. Verifier l'installation
./setup/verify-setup.sh

# 4. Creer le cluster kind
kind create cluster --config setup/kind-config.yaml --name training

# 5. Verifier le cluster
kubectl cluster-info
kubectl get nodes
```

---

## Utiliser kind entre les sessions

Le cluster kind vit dans Docker. Voici les commandes utiles :

```bash
# Lister les clusters
kind get clusters

# Supprimer le cluster (libere les ressources)
kind delete cluster --name training

# Recreer le cluster proprement avant une session
kind delete cluster --name training 2>/dev/null
kind create cluster --config setup/kind-config.yaml --name training

# Verifier que kubectl pointe sur le bon cluster
kubectl config current-context
# attendu : kind-training
```

> **Astuce** : si Docker est redemarre, le cluster kind est perdu. Il suffit de le recreer avec la commande ci-dessus.

---

## Structure du repo

```
k8s-training/
├── README.md                          # Ce fichier
├── SETUP.md                           # Guide d'installation detaille
├── .gitignore
├── app/
│   ├── api/                           # API Go (application fil rouge)
│   └── frontend/                      # Frontend React
├── labs/
│   ├── session-01-fundamentals/
│   │   ├── starter/                   # Fichiers de depart du lab
│   │   └── solution/                  # Solution complete
│   ├── session-02-services/
│   │   ├── starter/
│   │   └── solution/
│   ├── ...                            # Sessions 03 a 10
│   └── session-11-cicd/
│       ├── starter/
│       └── solution/
├── setup/
│   ├── prerequisites.sh               # Script d'installation des outils
│   ├── verify-setup.sh                # Verification de l'environnement
│   └── kind-config.yaml               # Configuration du cluster kind
├── cheatsheets/
│   ├── kubectl.md                     # Aide-memoire kubectl
│   ├── terraform.md                   # Aide-memoire Terraform
│   └── helm.md                        # Aide-memoire Helm
├── terraform/
│   └── student-template/              # Template Terraform pour les labs GKE
└── .github/
    └── ...
```

---

## Contact formateur

| | |
|---|---|
| **Nom** | _A completer_ |
| **Email** | _A completer_ |
| **Slack** | _A completer_ |

Pour toute question sur le contenu ou les labs, ouvrir une issue sur ce repo ou contacter le formateur directement.
