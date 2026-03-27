# Terraform -- Aide-memoire

## Workflow de base

```bash
# 1. Initialiser (telecharge providers + modules)
terraform init

# 2. Formater le code
terraform fmt

# 3. Valider la syntaxe
terraform validate

# 4. Planifier les changements
terraform plan

# 5. Planifier et sauvegarder dans un fichier
terraform plan -out=tfplan

# 6. Appliquer le plan
terraform apply tfplan

# 7. Appliquer directement (avec confirmation)
terraform apply

# 8. Appliquer sans confirmation (CI/CD)
terraform apply -auto-approve
```

## Gestion du state

```bash
# Lister toutes les ressources dans le state
terraform state list

# Details d'une ressource
terraform state show module.api.kubernetes_deployment.app

# Deplacer une ressource (renommage)
terraform state mv module.old_name module.new_name

# Supprimer une ressource du state (sans la detruire)
terraform state rm module.api.kubernetes_deployment.app

# Importer une ressource existante dans le state
terraform import module.api.kubernetes_deployment.app default/api

# Supprimer + reimporter (utile pour les erreurs d'identite)
terraform state rm module.api.kubernetes_deployment.app
terraform import module.api.kubernetes_deployment.app default/api
```

## Ciblage de ressources

```bash
# Planifier pour une seule ressource
terraform plan -target=module.api

# Appliquer pour une seule ressource
terraform apply -target=module.database

# Detruire une ressource specifique
terraform destroy -target=module.api
```

## Variables

```bash
# Passer une variable en ligne de commande
terraform plan -var="env=staging"

# Passer un fichier de variables
terraform plan -var-file="production.tfvars"

# Variables d'environnement (prefixe TF_VAR_)
export TF_VAR_env=staging
terraform plan
```

## Destruction

```bash
# Planifier la destruction
terraform plan -destroy

# Detruire toute l'infrastructure
terraform destroy

# Detruire sans confirmation (attention !)
terraform destroy -auto-approve
```

## Inspection & debug

```bash
# Afficher les outputs
terraform output

# Afficher un output specifique
terraform output -raw database_url

# Generer un graphe de dependances
terraform graph | dot -Tpng > graph.png

# Ouvrir la console interactive
terraform console
# > module.api.kubernetes_deployment.app.metadata[0].name

# Activer les logs detailles
TF_LOG=DEBUG terraform plan

# Afficher les providers utilises
terraform providers
```

## Formatage & validation

```bash
# Formater tous les fichiers .tf
terraform fmt

# Formater recursivement
terraform fmt -recursive

# Verifier le formatage (CI)
terraform fmt -check

# Valider la configuration
terraform validate
```

## Workspaces

```bash
# Lister les workspaces
terraform workspace list

# Creer un workspace
terraform workspace new staging

# Changer de workspace
terraform workspace select production

# Workspace courant
terraform workspace show
```

## Astuces

```bash
# Rafraichir le state sans appliquer
terraform refresh

# Remplacer une ressource (force recreate)
terraform apply -replace=module.api.kubernetes_deployment.app

# Verrouiller les versions des providers
terraform providers lock -platform=linux_amd64 -platform=darwin_amd64

# Afficher le plan en JSON (pour CI/CD)
terraform show -json tfplan

# Nettoyer le cache des plugins
rm -rf .terraform/
terraform init
```

## Structure type d'un projet

```
project/
├── main.tf           # Ressources principales
├── variables.tf      # Declaration des variables
├── outputs.tf        # Valeurs de sortie
├── providers.tf      # Configuration des providers
├── terraform.tfvars  # Valeurs des variables (non commite)
├── versions.tf       # Contraintes de versions
└── modules/
    ├── network/
    ├── cluster/
    └── application/
```
