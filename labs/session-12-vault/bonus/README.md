# Session 12 : exercices bonus

> Pour ceux qui ont terminé le lab en avance. Les deux exercices sont indépendants.

---

## Bonus 1 : la configuration Vault en Terraform (20 min)

Aux étapes 3 à 5, vous avez tout configuré à la main. En production, personne ne tape `vault write` : Terraform gère les politiques, les rôles et les static roles, et une nouvelle app, c'est une entrée de plus dans une map.

`terraform/main.tf` ajoute une deuxième app, `api2`, avec sa politique, son rôle Kubernetes auth et son static role. Trois ressources, un `for_each`.

### Préparer PostgreSQL et Vault

Le login `api2_app` doit exister, et Vault doit avoir le droit de le gérer (piège 8.4) et de l'utiliser (`allowed_roles`) :

```bash
kubectl -n exercices exec deploy/postgres -- psql -U postgres -d app -c \
  "CREATE ROLE api2_app WITH LOGIN PASSWORD 'remplace-par-vault' IN ROLE app_owner;
   ALTER ROLE api2_app SET role = 'app_owner';
   GRANT api2_app TO vault_admin WITH ADMIN OPTION;"

kubectl -n vault exec vault-0 -- env VAULT_TOKEN=root \
  vault write database/config/app allowed_roles="api,api-dynamic,api2"
```

### Appliquer

```bash
kubectl -n vault port-forward svc/vault 8200:8200 &
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root

cd terraform
terraform init
terraform plan     # 3 ressources à créer
terraform apply
```

Vérifiez :

```bash
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=root vault read database/static-creds/api2
kubectl -n vault exec vault-0 -- env VAULT_TOKEN=root vault policy read api2
```

### À essayer

- Ajoutez une troisième app dans `var.apps`. Que montre le `plan` ?
- Modifiez la politique à la main avec `vault policy write api2 ...`, puis relancez `terraform plan`. Terraform voit la dérive et propose de la corriger.
- Remplacez `rotation_period` par `rotation_schedule = "0 3 * * *"`. Pourquoi est-ce le bon réglage en production ? (Revoir l'étape 7.)

---

## Bonus 2 : une CI sans aucune clé (lecture, 15 min)

Ce bonus ne se fait pas sur kind : il faut un Vault joignable depuis GitHub Actions. On le lit, on comprend le mécanisme, et on le reconnaît quand on le croise.

### Le problème

Le pipeline qui lance `terraform apply` sur Vault a besoin d'un token Vault. Le stocker dans un secret GitHub, c'est un token longue durée, copié dans un système tiers, qu'il faudra penser à changer. Exactement ce que Vault est censé supprimer.

### Le mécanisme

GitHub Actions sait émettre, pour chaque exécution, un **token OIDC signé** qui dit : « je suis le dépôt `mon-org/infra`, sur la branche `main`, pour l'audience `vault` ». Il expire en quelques minutes. Vault sait vérifier cette signature (méthode `jwt`) et l'échanger contre un token Vault court.

```
GitHub Actions ──(token OIDC signé, quelques minutes)──► Vault jwt auth ──► token Vault d'1 h
                 "repo=mon-org/infra, ref=refs/heads/main"   vérifie la signature,
                                                              le dépôt et la branche
```

Côté Vault, une fois :

```bash
vault auth enable jwt

vault write auth/jwt/config \
  oidc_discovery_url="https://token.actions.githubusercontent.com" \
  bound_issuer="https://token.actions.githubusercontent.com"

vault write auth/jwt/role/terraform \
  role_type=jwt \
  user_claim=repository \
  bound_audiences=vault \
  bound_claims_type=glob \
  bound_claims='{"repository":"mon-org/infra","ref":"refs/heads/main"}' \
  token_policies=terraform \
  token_ttl=1h
```

Côté workflow :

```yaml
permissions:
  id-token: write   # autorise le job à demander un token OIDC
  contents: read

steps:
  - uses: hashicorp/vault-action@v3
    with:
      url: https://vault.interne.example
      method: jwt
      role: terraform
      jwtGithubAudience: vault
      exportToken: true
  - run: terraform apply -auto-approve
```

Plus aucun secret Vault dans GitHub. Une branche de fonctionnalité, un fork ou un autre dépôt présentent un token valide mais refusé par `bound_claims`.

### Ce que nous avons appris en le mettant en place

- **Le token OIDC est court.** Un `terraform plan` suivi d'un `apply` long peut dépasser sa durée de vie : notre pipeline en demande un avant le plan et un autre avant l'apply.
- **Vault sans adresse publique.** Notre Vault n'est pas exposé sur Internet. Le job rejoint d'abord le réseau privé de l'équipe comme nœud éphémère, avec un droit d'accès limité au seul port de Vault.
- **Même logique côté cloud.** Le même token OIDC remplace la clé JSON du compte de service GCP (Workload Identity Federation). Avant de supprimer l'ancienne clé, vérifiez qu'aucun autre dépôt ne s'en sert : nous avons coupé le déploiement d'une autre app en désactivant une clé partagée.
