# Session 11 : CI/CD avec GitHub Actions

## Objectifs

- Mettre en place un **pipeline CI/CD** complet avec GitHub Actions
- Automatiser le build, le push et le deploiement sur GKE
- Comprendre l'authentification GCP via **Workload Identity Federation**
- Optimiser le Dockerfile avec un **build multi-stage**
- Savoir effectuer un rollback en cas de probleme

## Pre-requis

- Un fork du repository `k8s-training` sur GitHub
- Cluster GKE fonctionnel avec le namespace `exercices`
- Artifact Registry configure dans le projet GCP (`europe-west9-docker.pkg.dev/cloud-447406/training`)
- Workload Identity Federation configure pour GitHub Actions

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

### 3. Completer le workflow GitHub Actions

Ouvrez `starter/.github/workflows/deploy.yml`. Completez les TODOs :

1. **Trigger** : declencher sur push vers `main`
2. **Authentification GCP** : utiliser `google-github-actions/auth` avec Workload Identity
3. **Build & Push** : construire l'image Docker et la pousser vers Artifact Registry
4. **Deploy** : mettre a jour l'image du Deployment avec `kubectl set image`

### 4. Configurer les secrets GitHub

Dans les settings de votre fork, ajoutez ces secrets :
- `GCP_WORKLOAD_IDENTITY_PROVIDER` : le provider Workload Identity
- `GCP_SERVICE_ACCOUNT` : le service account pour le deploiement

```bash
# Verifier les secrets (depuis votre fork)
gh secret list
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

Verifiez le deploiement :
```bash
kubectl get pods -n exercices -l app=api
kubectl rollout status deployment/api -n exercices
```

### 6. Provoquer un bug et faire un rollback

Introduisez un bug volontaire (ex: image inexistante) et poussez :
```bash
# Observez le pod en erreur
kubectl get pods -n exercices -l app=api

# Rollback vers la version precedente
kubectl rollout undo deployment/api -n exercices
kubectl rollout status deployment/api -n exercices
```

## Bonus

Ajoutez une etape `terraform plan` dans le workflow qui s'execute sur les Pull Requests et ajoute le plan en commentaire :

```yaml
- name: Terraform Plan
  if: github.event_name == 'pull_request'
  run: |
    cd labs/session-09-terraform-apps/solution
    terraform init
    terraform plan -no-color > plan.txt

- name: Comment PR with plan
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v7
  with:
    script: |
      const plan = require('fs').readFileSync('plan.txt', 'utf8');
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: '## Terraform Plan\n```\n' + plan + '\n```'
      });
```

## Mini-defi

Ajoutez une etape de **smoke test** apres le deploiement qui :
1. Attend 30 secondes que les pods soient prets
2. Fait un `curl` sur l'endpoint `/health` de l'API
3. Verifie que le status est `200`
4. Si le test echoue, effectue automatiquement un `kubectl rollout undo`

Exemple :
```yaml
- name: Smoke test
  run: |
    sleep 30
    STATUS=$(kubectl exec deploy/frontend -n exercices -- curl -s -o /dev/null -w "%{http_code}" http://api.exercices.svc.cluster.local/health)
    if [ "$STATUS" != "200" ]; then
      echo "Smoke test failed (HTTP $STATUS) — rolling back"
      kubectl rollout undo deployment/api -n exercices
      exit 1
    fi
    echo "Smoke test passed (HTTP $STATUS)"
```
