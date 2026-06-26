# Session 11 : CI/CD avec GitHub Actions

## Objectifs

- Mettre en place un **pipeline CI/CD** complet avec GitHub Actions
- Automatiser le build, le push et le deploiement sur GKE
- Comprendre l'authentification GCP via **Workload Identity Federation** (sans clé)
- Optimiser le Dockerfile avec un **build multi-stage**
- Savoir effectuer un rollback en cas de probleme

## Cluster partagé (le cas de la classe)

Comme en Session 9 et 10, on travaille sur le **cluster partagé** fourni par le
formateur. Vous deployez dans **votre namespace** `trainee-NN` — le même que
celui où tournent déjà votre `api` et votre `frontend` (Session 9).

La nouveauté de cette session, c'est que le déploiement n'est plus fait à la main
(`kubectl`) mais par un **pipeline GitHub Actions** qui s'authentifie à GCP en
**Workload Identity Federation** (pas de clé de service en clair).

Le formateur a provisionné une fois pour la classe (côté `cloud-infrastructure`,
`environments/training`) :

- le dépôt **Artifact Registry** `europe-west9-docker.pkg.dev/cloud-447406/training` ;
- un **pool + provider WIF** GitHub qui accepte **n'importe quel fork** nommé
  `k8s-training` ;
- un **service account de déploiement** (`training-deployer`) qui peut pousser
  des images et déployer dans les namespaces `trainee-NN`.

Le formateur vous donne **deux valeurs** (identiques pour toute la classe), à
mettre dans les secrets de **votre fork** :

| Secret GitHub | Valeur (sortie Terraform) |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `cicd_workload_identity_provider` |
| `GCP_SERVICE_ACCOUNT` | `cicd_deployer_service_account` |

## Pré-requis

- Un **fork** du dépôt `rflkt/k8s-training` sur GitHub
- Votre namespace `trainee-NN` avec l'`api` (Deployment) déjà déployé (Session 9)
- Les deux secrets ci-dessus configurés dans votre fork

> **Si l'`api` n'est plus déployée** dans votre namespace (le pipeline a besoin
> d'un Deployment nommé `api` à mettre à jour), appliquez la base de la Session 10
> — elle crée le Deployment `api`, son Service et un pod `frontend` :
> ```bash
> kubectl apply -f labs/session-10-production/solution/baseline.yaml -n trainee-NN
> ```

> **Sur votre propre cluster** (admin, comme en Session 8) : vous pouvez créer
> vous-même le dépôt Artifact Registry et le WIF (voir le bonus 1 du dépôt
> `cloud-infrastructure`), et utiliser le namespace de votre choix. Le reste du
> TP est identique.

## Etapes

### 1. Forker le repository

Si ce n'est pas deja fait, forkez le repository et clonez votre fork :
```bash
gh repo fork rflkt/k8s-training --clone
cd k8s-training
```

### 2. Optimiser le Dockerfile

Consultez le Dockerfile multi-stage dans `app/api/Dockerfile.multistage`.

Ce Dockerfile utilise deux etapes :
1. **Build stage** : compile le binaire Go de facon statique (`CGO_ENABLED=0`)
2. **Runtime stage** : utilise l'image `scratch` (vide) pour un resultat minimal

Comparez les tailles d'image :
```bash
# Build standard
docker build -t api:standard -f app/api/Dockerfile app/api/
# Build multi-stage
docker build -t api:optimized -f app/api/Dockerfile.multistage app/api/

docker images | grep api
```

### 3. Configurer les secrets GitHub

Dans les settings de votre fork (**Settings → Secrets and variables → Actions**),
ajoutez les deux secrets donnés par le formateur :
- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`

```bash
# Verifier les secrets (depuis votre fork)
gh secret list
```

### 4. Completer le workflow GitHub Actions

Ouvrez `starter/.github/workflows/deploy.yml`. **Mettez d'abord `NAMESPACE` à
votre namespace** (`trainee-NN`), puis completez les TODOs :

1. **Trigger** : declencher sur push vers `main`
2. **Authentification GCP** : `google-github-actions/auth` avec Workload Identity
3. **Build & Push** : construire l'image (multi-stage) et la pousser vers Artifact Registry
4. **Deploy** : mettre a jour l'image du Deployment avec `kubectl set image` dans **votre** namespace

Copiez votre workflow complété à l'emplacement attendu par GitHub Actions :
```bash
mkdir -p .github/workflows
cp labs/session-11-cicd/starter/.github/workflows/deploy.yml .github/workflows/deploy.yml
```

### 5. Pousser et observer le deploiement automatique

```bash
# Faites une modification dans l'API (ex: changez le message dans handleRoot)
# Puis poussez sur main
git add .
git commit -m "feat: update API welcome message"
git push origin main
```

Observez le workflow dans GitHub Actions :
```bash
gh run list --limit 5
gh run watch
```

Verifiez le deploiement (remplacez `trainee-NN` par votre namespace) :
```bash
export NS=trainee-NN
kubectl get pods -n $NS -l app=api
kubectl rollout status deployment/api -n $NS
```

### 6. Provoquer un bug et faire un rollback

Introduisez un bug volontaire (ex: image inexistante) et poussez :
```bash
# Observez le pod en erreur
kubectl get pods -n $NS -l app=api

# Rollback vers la version precedente
kubectl rollout undo deployment/api -n $NS
kubectl rollout status deployment/api -n $NS
```

## Bonus

Voir [les exercices bonus](./bonus/README.md) : `terraform plan` en commentaire de
PR, smoke test avec auto-rollback, matrix multi-environnement, et notifications.

## Mini-defi

Ajoutez une etape de **smoke test** apres le deploiement qui :
1. Attend que les pods soient prets (`kubectl rollout status`)
2. Fait un appel HTTP sur l'endpoint `/health` de l'API depuis l'intérieur du cluster
3. Verifie que le status est `200`
4. Si le test echoue, effectue automatiquement un `kubectl rollout undo`

Exemple (le pod `frontend` est une image `nginx:alpine` **sans `curl`** : on
utilise `wget`, fourni par BusyBox) :
```yaml
- name: Smoke test
  run: |
    kubectl rollout status deployment/api -n $NAMESPACE --timeout=120s
    STATUS=$(kubectl exec deploy/frontend -n $NAMESPACE -- \
      wget -qO- --server-response --timeout=5 \
      http://api.$NAMESPACE.svc.cluster.local/health 2>&1 | awk '/HTTP\//{print $2; exit}')
    if [ "$STATUS" != "200" ]; then
      echo "Smoke test failed (HTTP $STATUS) — rolling back"
      kubectl rollout undo deployment/api -n $NAMESPACE
      exit 1
    fi
    echo "Smoke test passed (HTTP $STATUS)"
```
