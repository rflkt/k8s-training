# Politique Vault de l'API : lire SON chemin KV et SON login base de donnees.
# Rien d'autre. Une app = une politique = un role.

# KV v2 : le chemin d'API contient "data/" entre le mount et le chemin logique.
path "kv/data/exercices/api" {
  capabilities = ["read"]
}

# Le login base de donnees dont Vault fait tourner le mot de passe.
path "database/static-creds/api" {
  capabilities = ["read"]
}
