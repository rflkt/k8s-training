# Session 6 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.
> Pensez a remplacer `<NOM>` par votre prenom dans tous les fichiers YAML et commandes.

> **Note** : sur le cluster partage, les trainees ne peuvent pas creer de namespaces ni de Service Accounts GCP. Certains exercices supposent que le formateur a deja prepare l'environnement (indique le cas echeant).

---

## Bonus 1 : ExternalSecret avec template et type dedie (15 min)

ESO permet de transformer la structure du Secret K8s genere via la section `template`. Utile quand l'application attend un format specifique (ex: `kubernetes.io/dockerconfigjson`, un fichier `.env`, du YAML, etc.).

Creez un `ExternalSecret` qui combine plusieurs cles GCP en un fichier `.env` materialise comme cle unique :

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-dotenv-<NOM>
  namespace: exercices
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: gcp-secret-store-<NOM>
    kind: SecretStore
  target:
    name: app-dotenv-<NOM>
    creationPolicy: Owner
    template:
      engineVersion: v2
      type: Opaque
      data:
        # Concatene les 3 secrets en un seul fichier .env
        # | trim retire le \n final que GCP Secret Manager ajoute sur certaines valeurs
        .env: |
          DB_PASSWORD={{ .db_password | trim }}
          API_KEY={{ .api_key | trim }}
          OAUTH_TOKEN={{ .oauth_token | trim }}
  data:
    - secretKey: db_password
      remoteRef:
        key: training-db-password
    - secretKey: api_key
      remoteRef:
        key: training-api-key
    - secretKey: oauth_token
      remoteRef:
        key: training-oauth-token
```

Appliquez puis lisez la cle `.env` resultante :

```bash
kubectl apply -f app-dotenv.yaml
kubectl get secret app-dotenv-<NOM> -n exercices \
  -o jsonpath='{.data.\.env}' | base64 -d
```

**Question** : Quel est l'avantage d'un Secret materialise en `.env` plutot qu'en cles separees ? Citez un cas d'usage reel.

---

## Bonus 2 : Multiples ExternalSecret avec rafraichissement decale (15 min)

Creez deux `ExternalSecret` differents avec des `refreshInterval` distincts pour observer la difference de comportement :

- `api-secret-fast-<NOM>` : `refreshInterval: 30s`, ne sync que `training-api-key`
- `api-secret-slow-<NOM>` : `refreshInterval: 10m`, ne sync que `training-api-key`

Demandez au formateur de modifier le secret GCP, puis comparez :

```bash
# Le rapide se met a jour dans la minute
kubectl get secret api-secret-fast-<NOM> -n exercices \
  -o jsonpath='{.data.API_KEY}' | base64 -d

# Le lent garde l'ancienne valeur jusqu'au prochain cycle de 10 min
kubectl get secret api-secret-slow-<NOM> -n exercices \
  -o jsonpath='{.data.API_KEY}' | base64 -d
```

**Question** : Comment choisir un bon `refreshInterval` ? Quels sont les compromis entre fraicheur des donnees, charge sur l'API GCP, et cout ?

---

## Bonus 3 : Monitoring et debug d'un ExternalSecret (15 min)

Explorez les outils de diagnostic d'ESO.

1. Inspectez le statut detaille d'un ExternalSecret :

```bash
kubectl describe externalsecret api-secrets-<NOM> -n exercices
# Regardez Conditions, RefreshTime, Events
```

2. Lisez les logs du controleur ESO :

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets \
  --tail=50 | grep -i "<NOM>"
```

3. Simulez une erreur en pointant vers un secret GCP inexistant :

```yaml
# Modifiez votre ExternalSecret pour referencer un secret qui n'existe pas
data:
  - secretKey: BAD
    remoteRef:
      key: training-does-not-exist
```

Observez le status :

```bash
kubectl get externalsecret api-secrets-<NOM> -n exercices \
  -o jsonpath='{.status.conditions}' | jq .
```

**Question** : Quels signaux utiliseriez-vous en production pour alerter sur un ExternalSecret en panne (status != Ready, refresh failures, etc.) ?

---

## Bonus 4 : ClusterSecretStore (concept) (10 min)

> **Important** : la creation d'un ClusterSecretStore necessite des permissions cluster-admin que les trainees n'ont pas. Cet exercice est conceptuel — discutez l'architecture, n'essayez pas de creer la ressource.

Un `ClusterSecretStore` est un `SecretStore` cluster-scoped : un seul objet utilisable depuis n'importe quel namespace.

Avantages :
- Un seul point de configuration pour tous les namespaces
- Pas besoin de dupliquer la config provider dans chaque namespace
- Le ServiceAccount K8s referenced peut etre dans un namespace dedie

Risques :
- Si le ClusterSecretStore est compromis, toutes les apps du cluster sont exposees
- La granularite IAM est plus difficile a maintenir (un seul SA pour beaucoup d'usages)
- Faible isolation entre namespaces / equipes

Question d'architecture : dans quel contexte recommanderiez-vous un `ClusterSecretStore` plutot que des `SecretStore` par namespace ?
- Petite equipe, peu de namespaces : `ClusterSecretStore` est simple et efficace
- Multi-tenant, plusieurs equipes : `SecretStore` par namespace (isolation)
- Multi-provider : peut etre necessaire de combiner les deux
