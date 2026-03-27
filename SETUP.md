# Guide d'installation

Instructions detaillees pour preparer votre environnement de travail. Trois plateformes supportees : **macOS**, **Linux** (Ubuntu/Debian) et **Windows** (via WSL2).

> **Raccourci** : sur Mac ou Linux, le script `./setup/prerequisites.sh` installe tout automatiquement.

---

## Table des matieres

1. [Docker](#1-docker)
2. [kubectl](#2-kubectl)
3. [kind](#3-kind)
4. [Helm](#4-helm)
5. [Terraform](#5-terraform)
6. [gcloud CLI](#6-gcloud-cli)
7. [VS Code + extensions](#7-vs-code--extensions)
8. [Verification](#8-verification)

---

## 1. Docker

Moteur de conteneurs necessaire pour faire tourner les clusters kind en local.

### macOS

```bash
brew install --cask docker
# Lancer Docker Desktop depuis Applications
```

### Linux (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
# Se deconnecter/reconnecter pour que le groupe prenne effet
```

Alternative : installer [Docker Desktop pour Linux](https://docs.docker.com/desktop/install/linux-install/) ou [Rancher Desktop](https://rancherdesktop.io/).

### Windows (WSL2)

1. Installer [Docker Desktop pour Windows](https://www.docker.com/products/docker-desktop/)
2. Dans Settings > Resources > WSL Integration, activer votre distribution WSL2
3. Verifier depuis le terminal WSL

### Verification

```bash
docker --version
# Docker version 27.x.x
docker run hello-world
```

---

## 2. kubectl

Client en ligne de commande pour interagir avec les clusters Kubernetes.

### macOS

```bash
brew install kubectl
```

### Linux

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

Ou via apt :

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
```

### Windows (WSL2)

Suivre les instructions Linux ci-dessus depuis votre terminal WSL2.

### Verification

```bash
kubectl version --client
# Client Version: v1.31.x
```

---

## 3. kind

**Kubernetes IN Docker** -- cree des clusters K8s multi-noeuds dans des conteneurs Docker.

### macOS

```bash
brew install kind
```

### Linux

```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

### Windows (WSL2)

Suivre les instructions Linux ci-dessus depuis votre terminal WSL2.

### Verification

```bash
kind --version
# kind v0.25.x
```

---

## 4. Helm

Gestionnaire de packages pour Kubernetes. Utilise pour installer Traefik, monitoring, etc.

### macOS

```bash
brew install helm
```

### Linux

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Windows (WSL2)

Suivre les instructions Linux ci-dessus depuis votre terminal WSL2.

### Verification

```bash
helm version
# version.BuildInfo{Version:"v3.16.x", ...}
```

---

## 5. Terraform

Outil d'Infrastructure as Code utilise dans les sessions 07-09 pour provisionner des clusters GKE.

**Version requise** : >= 1.13

### macOS

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

### Linux

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform
```

### Windows (WSL2)

Suivre les instructions Linux ci-dessus depuis votre terminal WSL2.

### Verification

```bash
terraform version
# Terraform v1.13.x
```

---

## 6. gcloud CLI

SDK Google Cloud pour l'authentification et la gestion des ressources GCP.

### macOS

```bash
brew install --cask google-cloud-sdk
```

### Linux

```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

### Windows (WSL2)

```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init
```

### Verification

```bash
gcloud version
# Google Cloud SDK 5xx.x.x
```

### Configuration initiale

```bash
# Authentification
gcloud auth login

# Configurer le projet (sera communique par le formateur)
gcloud config set project <PROJECT_ID>

# Installer le plugin GKE auth
gcloud components install gke-gcloud-auth-plugin
```

---

## 7. VS Code + extensions

Editeur recommande. Installer depuis [code.visualstudio.com](https://code.visualstudio.com/).

### Extensions recommandees

Installer via la ligne de commande :

```bash
code --install-extension ms-kubernetes-tools.vscode-kubernetes-tools
code --install-extension redhat.vscode-yaml
code --install-extension hashicorp.terraform
code --install-extension golang.go
```

| Extension | Description |
|-----------|-------------|
| **Kubernetes** (ms-kubernetes-tools) | Navigation dans les clusters, manifestes, logs |
| **YAML** (redhat) | Validation et autocompletion des manifestes K8s |
| **HashiCorp Terraform** | Syntax highlighting, autocompletion, formatting |
| **Go** | Support complet du langage Go pour l'app fil rouge |

---

## 8. Verification

Lancer le script de verification pour valider l'ensemble :

```bash
./setup/verify-setup.sh
```

Resultat attendu :

```
=== Verification de l'environnement ===
  docker         27.5.1       OK
  kubectl        v1.31.4      OK
  kind           v0.25.0      OK
  helm           v3.16.3      OK
  terraform      v1.13.1      OK
  gcloud         512.0.0      OK

Tous les outils sont installes. Vous etes pret(e) !
```

Si un outil manque, suivre les instructions de la section correspondante ci-dessus ou relancer `./setup/prerequisites.sh`.
