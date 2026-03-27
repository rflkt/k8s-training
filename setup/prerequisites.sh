#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# prerequisites.sh -- Installe les outils pour la formation K8s
# Supporte macOS (brew) et Linux/Ubuntu (apt + binaires)
# Idempotent : ne reinstalle pas ce qui est deja present
# ============================================================

# -- Couleurs ------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ok()   { echo -e "  ${GREEN}OK${NC}    $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; }
err()  { echo -e "  ${RED}ERROR${NC} $1"; }
info() { echo -e "  ${BLUE}-->${NC}   $1"; }

# -- Detection OS -------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "mac" ;;
        Linux*)  echo "linux" ;;
        *)       echo "unknown" ;;
    esac
}

OS=$(detect_os)

if [[ "$OS" == "unknown" ]]; then
    err "Systeme non supporte : $(uname -s)"
    err "Ce script supporte macOS et Linux (Ubuntu/Debian)."
    exit 1
fi

echo ""
echo -e "${BOLD}=== Installation des prerequis ($(uname -s)) ===${NC}"
echo ""

# -- Helpers ------------------------------------------------
command_exists() {
    command -v "$1" &>/dev/null
}

install_brew_if_needed() {
    if ! command_exists brew; then
        info "Installation de Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

# -- Docker -------------------------------------------------
install_docker() {
    if command_exists docker; then
        ok "docker deja installe ($(docker --version 2>/dev/null | head -1))"
        return
    fi

    if [[ "$OS" == "mac" ]]; then
        install_brew_if_needed
        info "Installation de Docker Desktop..."
        brew install --cask docker
        warn "Lancer Docker Desktop depuis Applications avant de continuer"
    else
        info "Installation de docker.io..."
        sudo apt-get update -qq
        sudo apt-get install -y -qq docker.io
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        warn "Deconnectez-vous et reconnectez-vous pour que le groupe docker prenne effet"
    fi
    ok "docker installe"
}

# -- kubectl ------------------------------------------------
install_kubectl() {
    if command_exists kubectl; then
        ok "kubectl deja installe ($(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1))"
        return
    fi

    if [[ "$OS" == "mac" ]]; then
        install_brew_if_needed
        brew install kubectl
    else
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi
    ok "kubectl installe"
}

# -- kind ---------------------------------------------------
install_kind() {
    if command_exists kind; then
        ok "kind deja installe ($(kind --version 2>/dev/null))"
        return
    fi

    if [[ "$OS" == "mac" ]]; then
        install_brew_if_needed
        brew install kind
    else
        curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.25.0/kind-linux-amd64
        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind
    fi
    ok "kind installe"
}

# -- Helm ---------------------------------------------------
install_helm() {
    if command_exists helm; then
        ok "helm deja installe ($(helm version --short 2>/dev/null))"
        return
    fi

    if [[ "$OS" == "mac" ]]; then
        install_brew_if_needed
        brew install helm
    else
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    ok "helm installe"
}

# -- Terraform ----------------------------------------------
install_terraform() {
    if command_exists terraform; then
        ok "terraform deja installe ($(terraform version -json 2>/dev/null | grep '"terraform_version"' | cut -d'"' -f4 || terraform version 2>/dev/null | head -1))"
        return
    fi

    if [[ "$OS" == "mac" ]]; then
        install_brew_if_needed
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform
    else
        wget -O - https://apt.releases.hashicorp.com/gpg 2>/dev/null | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt-get update -qq
        sudo apt-get install -y -qq terraform
    fi
    ok "terraform installe"
}

# -- gcloud CLI ---------------------------------------------
install_gcloud() {
    if command_exists gcloud; then
        ok "gcloud deja installe ($(gcloud version 2>/dev/null | head -1))"
        return
    fi

    if [[ "$OS" == "mac" ]]; then
        install_brew_if_needed
        brew install --cask google-cloud-sdk
    else
        info "Installation de gcloud CLI..."
        curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
        warn "Executez 'exec -l \$SHELL' puis 'gcloud init' apres le script"
    fi
    ok "gcloud installe"
}

# -- Execution ----------------------------------------------
install_docker
install_kubectl
install_kind
install_helm
install_terraform
install_gcloud

# -- Resume -------------------------------------------------
echo ""
echo -e "${BOLD}=== Resume des versions ===${NC}"
echo ""

declare -a TOOLS=("docker" "kubectl" "kind" "helm" "terraform" "gcloud")

for tool in "${TOOLS[@]}"; do
    if command_exists "$tool"; then
        case "$tool" in
            docker)    ver=$(docker --version 2>/dev/null | sed 's/Docker version //' | cut -d',' -f1) ;;
            kubectl)   ver=$(kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1) ;;
            kind)      ver=$(kind --version 2>/dev/null | awk '{print $NF}') ;;
            helm)      ver=$(helm version --short 2>/dev/null | cut -d'+' -f1) ;;
            terraform) ver=$(terraform version 2>/dev/null | head -1 | awk '{print $NF}') ;;
            gcloud)    ver=$(gcloud version 2>/dev/null | head -1 | awk '{print $NF}') ;;
        esac
        printf "  ${GREEN}OK${NC}  %-14s %s\n" "$tool" "$ver"
    else
        printf "  ${RED}!!${NC}  %-14s %s\n" "$tool" "non installe"
    fi
done

echo ""
echo -e "${GREEN}${BOLD}Installation terminee.${NC} Lancez ${BOLD}./setup/verify-setup.sh${NC} pour valider."
echo ""
