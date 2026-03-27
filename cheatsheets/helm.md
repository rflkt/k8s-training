# Helm -- Aide-memoire

## Gestion des repos

```bash
# Ajouter un repo
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add traefik https://traefik.github.io/charts

# Mettre a jour les repos
helm repo update

# Lister les repos configures
helm repo list

# Chercher un chart
helm search repo traefik

# Chercher sur le hub public
helm search hub postgresql

# Supprimer un repo
helm repo remove bitnami
```

## Installation

```bash
# Installer un chart avec un nom de release
helm install my-release bitnami/postgresql

# Installer dans un namespace specifique
helm install traefik traefik/traefik -n traefik --create-namespace

# Installer avec des valeurs personnalisees
helm install api ./charts/api -f values-staging.yaml

# Installer avec des valeurs en ligne
helm install api ./charts/api --set replicas=3 --set image.tag=v2

# Installer en mode dry-run (preview)
helm install api ./charts/api --dry-run

# Installer et attendre que les pods soient ready
helm install api ./charts/api --wait --timeout 5m

# Generer un nom de release automatiquement
helm install bitnami/postgresql --generate-name
```

## Mise a jour (upgrade)

```bash
# Mettre a jour une release
helm upgrade api ./charts/api -f values-production.yaml

# Installer ou mettre a jour (idempotent)
helm upgrade --install api ./charts/api -f values.yaml

# Mettre a jour avec reset des valeurs par defaut
helm upgrade api ./charts/api --reset-values

# Mettre a jour en conservant les valeurs actuelles
helm upgrade api ./charts/api --reuse-values --set image.tag=v3
```

## Rollback

```bash
# Voir l'historique d'une release
helm history api

# Rollback a la revision precedente
helm rollback api

# Rollback a une revision specifique
helm rollback api 2

# Rollback et attendre
helm rollback api 2 --wait --timeout 3m
```

## Inspection

```bash
# Lister les releases installees
helm list

# Lister dans tous les namespaces
helm list -A

# Statut d'une release
helm status api

# Voir les valeurs d'une release deployee
helm get values api

# Voir toutes les valeurs (defaut + custom)
helm get values api --all

# Voir les manifestes generes
helm get manifest api

# Voir les notes post-install
helm get notes api
```

## Valeurs (values)

```bash
# Voir les valeurs par defaut d'un chart
helm show values bitnami/postgresql

# Voir le README d'un chart
helm show readme traefik/traefik

# Voir toutes les infos d'un chart
helm show all traefik/traefik

# Telecharger les valeurs par defaut dans un fichier
helm show values bitnami/postgresql > values.yaml
```

## Template & debug

```bash
# Rendre les templates sans installer (debug)
helm template api ./charts/api -f values.yaml

# Rendre un seul template
helm template api ./charts/api -s templates/deployment.yaml

# Rendre avec les notes
helm template api ./charts/api --show-only templates/NOTES.txt

# Dry-run cote serveur (validation K8s)
helm install api ./charts/api --dry-run=server

# Linter le chart
helm lint ./charts/api

# Linter avec des valeurs
helm lint ./charts/api -f values-production.yaml
```

## Creation de charts

```bash
# Creer un nouveau chart
helm create mon-chart

# Structure generee :
# mon-chart/
# ├── Chart.yaml          # Metadata du chart
# ├── values.yaml         # Valeurs par defaut
# ├── charts/             # Dependances
# ├── templates/          # Templates K8s
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   ├── ingress.yaml
# │   ├── _helpers.tpl    # Fonctions template
# │   └── NOTES.txt       # Notes post-install
# └── .helmignore

# Packager un chart
helm package ./charts/api

# Mettre a jour les dependances
helm dependency update ./charts/api

# Lister les dependances
helm dependency list ./charts/api
```

## Suppression

```bash
# Desinstaller une release
helm uninstall api

# Desinstaller dans un namespace specifique
helm uninstall traefik -n traefik

# Desinstaller en gardant l'historique
helm uninstall api --keep-history
```

## Astuces

```bash
# Comparer les changements avant upgrade
helm diff upgrade api ./charts/api -f values.yaml
# (necessite le plugin helm-diff : helm plugin install https://github.com/databus23/helm-diff)

# Exporter les valeurs actuelles avant de modifier
helm get values api -o yaml > current-values.yaml

# Installer un plugin
helm plugin install https://github.com/databus23/helm-diff

# Lister les plugins
helm plugin list
```
