#!/usr/bin/env bash
# Rattrapage : configure Vault exactement comme les etapes 3 a 5 du README.
# Prerequis : etapes 1 et 2 faites (Vault, CSI driver et PostgreSQL Running).
# Usage : ./solution/vault-setup.sh   (depuis labs/session-12-vault)
set -euo pipefail
cd "$(dirname "$0")"

v() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN=root vault "$@"; }

echo "== Etape 3 : KV v2 et un premier secret"
v secrets enable -path=kv kv-v2 2>/dev/null || echo "(kv deja active)"
v kv put kv/exercices/api API_KEY="cle-api-$(date +%s)"

echo "== Etape 4 : Kubernetes auth, politique et role de l'API"
v auth enable kubernetes 2>/dev/null || echo "(kubernetes auth deja active)"
v write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc"
v policy write api - < policy-api.hcl
v write auth/kubernetes/role/api \
  bound_service_account_names=api \
  bound_service_account_namespaces=exercices \
  audience=vault \
  token_policies=api \
  token_ttl=20m

echo "== Etape 5 : moteur database, rotation root, static et dynamic roles"
v secrets enable database 2>/dev/null || echo "(database deja active)"
v write database/config/app \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres.exercices.svc.cluster.local:5432/app?sslmode=disable" \
  allowed_roles="api,api-dynamic" \
  username=vault_admin \
  password=bootstrap-password-rotated-by-vault
v write -force database/rotate-root/app || echo "(rotation root deja faite)"
v write database/static-roles/api db_name=app username=api_app rotation_period=120s
v write database/roles/api-dynamic db_name=app default_ttl=2m max_ttl=10m \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE app_owner; ALTER ROLE \"{{name}}\" SET role = 'app_owner';" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";"

echo "OK. Suite du lab : etape 6."
