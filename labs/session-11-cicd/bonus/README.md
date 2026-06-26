# Session 11 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.
>
> On reste sur le **cluster partagé** : on déploie dans **votre** namespace
> `trainee-NN`, auth en **Workload Identity Federation** (les deux secrets du TP
> principal). Remplacez `trainee-NN` par votre namespace partout.

---

## Bonus 1 : Ajouter Terraform Plan en commentaire PR (20 min)

Intégrez un **terraform plan automatique** dans vos Pull Requests pour reviewer les changements avant le merge :

1. Dans votre fork, creez `.github/workflows/terraform-plan.yml` :

```yaml
name: Terraform Plan on PR

on:
  pull_request:
    paths:
      - 'labs/session-09-terraform-apps/**'
      - '.github/workflows/terraform-plan.yml'

permissions:
  contents: read
  pull-requests: write
  id-token: write

jobs:
  terraform-plan:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0

      - name: Terraform Init
        working-directory: labs/session-09-terraform-apps/solution
        run: terraform init

      - name: Terraform Plan
        id: tf-plan
        working-directory: labs/session-09-terraform-apps/solution
        run: |
          terraform plan -no-color > plan.txt 2>&1 || true
          {
            echo "plan_output<<EOF"
            cat plan.txt
            echo "EOF"
          } >> "$GITHUB_OUTPUT"

      - name: Comment PR with Plan
        uses: actions/github-script@v7
        with:
          script: |
            const plan = `${{ steps.tf-plan.outputs.plan_output }}`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## Terraform Plan\n```\n' + plan + '\n```'
            });
```

2. Creez une PR sur votre fork, poussez un changement Terraform, et observez le
   commentaire automatique se créer puis se mettre à jour.

```bash
gh pr create --title "Test terraform plan" --body "Testing the plan automation"
gh run list --workflow=terraform-plan.yml
gh pr view --web
```

**Question** : Comment cette automatisation aide-t-elle lors du code review ?
Quelles informations supplementaires ajouteriez-vous (ex: estimations de coût) ?

---

## Bonus 2 : Smoke test post-deploiement avec auto-rollback (20 min)

Ajoutez à **votre** `deploy.yml` une **etape de smoke test** qui valide le
deploiement et **rollback automatiquement** en cas d'erreur. Ajoutez ces étapes
**après** le `kubectl set image` (le pod `frontend` est une image
`nginx:alpine` **sans `curl`** : on utilise `wget`, fourni par BusyBox) :

```yaml
      - name: Smoke test - Health check
        id: smoke
        run: |
          kubectl rollout status deployment/api -n $NAMESPACE --timeout=120s
          STATUS=$(kubectl exec deploy/frontend -n $NAMESPACE -- \
            wget -qO- --server-response --timeout=5 \
            http://api.$NAMESPACE.svc.cluster.local/health 2>&1 \
            | awk '/HTTP\//{print $2; exit}')
          echo "Health check HTTP status: $STATUS"
          [ "$STATUS" = "200" ] || { echo "Smoke test FAILED"; exit 1; }
          echo "Smoke test PASSED"

      - name: Rollback on failure
        if: failure()
        run: |
          echo "Deploiement echoue — rollback automatique..."
          kubectl rollout undo deployment/api -n $NAMESPACE
          kubectl rollout status deployment/api -n $NAMESPACE --timeout=120s
```

> `$NAMESPACE` est l'`env` déjà défini en haut du workflow (votre `trainee-NN`).

Testez le rollback en introduisant un bug (ex: une image qui ne démarre pas) puis
poussez sur `main` :

```bash
kubectl rollout history deployment/api -n trainee-NN
kubectl get pods -n trainee-NN -l app=api
```

**Question** : Quels autres tests incluiriez-vous dans un smoke test (endpoints
critiques, dépendances) ? Comment eviter les faux positifs ?

---

## Bonus 3 : Matrix strategy pour multi-environnement (15 min)

> **Illustratif.** Ce workflow montre la *syntaxe* d'une matrix multi-environnement.
> Les clusters `dev`/`staging`/`prod` n'existent pas dans la classe — c'est le
> pattern qu'on utilise en vrai chez RFLKT (cf. la slide « Walkthrough RFLKT »),
> pas un exercice à exécuter sur le cluster partagé.

Utilisez une **matrix** pour déployer dans plusieurs environnements en parallèle :

```yaml
name: Multi-environment Deploy

on:
  push:
    branches:
      - main

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    strategy:
      matrix:
        environment:
          - { name: dev,        cluster: dev-cluster,     namespace: dev }
          - { name: staging,    cluster: staging-cluster, namespace: staging }
          - { name: production, cluster: prod-cluster,    namespace: production }

    runs-on: ubuntu-latest
    environment: ${{ matrix.environment.name }}

    steps:
      - uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Get GKE credentials for ${{ matrix.environment.name }}
        uses: google-github-actions/get-gke-credentials@v2
        with:
          cluster_name: ${{ matrix.environment.cluster }}
          location: europe-west9-b

      - name: Deploy to ${{ matrix.environment.name }}
        run: |
          kubectl set image deployment/api \
            api=europe-west9-docker.pkg.dev/cloud-447406/training/api:${{ github.sha }} \
            -n ${{ matrix.environment.namespace }}
          kubectl rollout status deployment/api -n ${{ matrix.environment.namespace }} --timeout=120s
```

Pour enchaîner (prod **après** staging OK), ajoutez un `needs:` entre jobs séparés.

**Question** : Avantages d'une matrix ? Comment gérer des secrets différents par
environnement ? Quand ajouter une approval manuelle avant prod (`environment:` +
required reviewers) ?

---

## Bonus 4 : Notifications et alertes de deploiement (15 min)

Ajoutez des **notifications post-deploiement** pour alerter l'équipe via Slack :

```yaml
      - name: Notify Slack on success
        if: success()
        uses: 8398a7/action-slack@v3
        with:
          status: success
          text: |
            Deploiement reussi — ${{ github.repository }}
            Commit: ${{ github.sha }} par ${{ github.actor }}
          fields: repo,message,commit,author
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}

      - name: Notify Slack on failure
        if: failure()
        uses: 8398a7/action-slack@v3
        with:
          status: failure
          text: |
            Deploiement ECHOUE — ${{ github.repository }}
            Logs: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
          fields: repo,message,commit,author
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

Configurez le secret `SLACK_WEBHOOK` dans votre fork (un webhook Slack entrant).

**Question** : Quels autres canaux en production (Teams, Discord, PagerDuty,
Datadog) ? Comment eviter le spam de notifications si un deploiement est retenté ?
