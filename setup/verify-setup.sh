#!/usr/bin/env bash
set -uo pipefail

# ============================================================
# verify-setup.sh -- Verifie que tous les outils sont installes
# Exit code 1 si un outil obligatoire manque
# ============================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

echo ""
echo -e "${BOLD}=== Verification de l'environnement ===${NC}"
echo ""

check_tool() {
    local name="$1"
    local cmd="$2"
    local version_cmd="$3"

    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$(eval "$version_cmd" 2>/dev/null || echo "version inconnue")
        printf "  \xE2\x9C\x85  %-14s %-16s ${GREEN}OK${NC}\n" "$name" "$ver"
        PASS=$((PASS + 1))
    else
        printf "  \xE2\x9D\x8C  %-14s %-16s ${RED}MANQUANT${NC}\n" "$name" "--"
        FAIL=$((FAIL + 1))
    fi
}

check_tool "docker" "docker" \
    "docker --version | sed 's/Docker version //' | cut -d',' -f1"

check_tool "kubectl" "kubectl" \
    "kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1"

check_tool "kind" "kind" \
    "kind --version | awk '{print \$NF}'"

check_tool "helm" "helm" \
    "helm version --short 2>/dev/null | cut -d'+' -f1"

check_tool "terraform" "terraform" \
    "terraform version 2>/dev/null | head -1 | awk '{print \$NF}'"

check_tool "gcloud" "gcloud" \
    "gcloud version 2>/dev/null | head -1 | awk '{print \$NF}'"

echo ""
echo "-------------------------------------------"

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${RED}${BOLD}$FAIL outil(s) manquant(s).${NC} Consultez SETUP.md ou lancez ./setup/prerequisites.sh"
    echo ""
    exit 1
else
    echo -e "${GREEN}${BOLD}Tous les outils sont installes. Vous etes pret(e) !${NC}"
    echo ""
    exit 0
fi
