# Session 11 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : Ajouter Terraform Plan en commentaire PR (20 min)

Intégrez un **terraform plan automatique** dans vos Pull Requests pour reviewer les changements avant le merge :

1. Dans votre fork, creez/modifiez `.github/workflows/terraform-plan.yml` :

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

jobs:
  terraform-plan:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0

      - name: Terraform Init
        working-directory: labs/session-09-terraform-apps/solution
        run: terraform init

      - name: Terraform Plan
        working-directory: labs/session-09-terraform-apps/solution
        run: terraform plan -no-color > plan.txt
        env:
          TF_VAR_project_id: ${{ secrets.GCP_PROJECT_ID }}

      - name: Read Plan Output
        id: tf-plan
        run: |
          echo "plan_output<<EOF" >> $GITHUB_OUTPUT
          cat labs/session-09-terraform-apps/solution/plan.txt >> $GITHUB_OUTPUT
          echo "EOF" >> $GITHUB_OUTPUT

      - name: Comment PR with Plan
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          script: |
            const plan = `${{ steps.tf-plan.outputs.plan_output }}`;
            const comment = `## Terraform Plan
            
\`\`\`
${plan}
\`\`\``;
            
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: comment
            });
```

2. Committez et poussez le workflow :

```bash
git add .github/workflows/terraform-plan.yml
git commit -m "ci: add terraform plan to PRs"
git push origin feature-branch
```

3. Creez une Pull Request sur votre fork :

```bash
gh pr create --title "Test terraform plan in PR" --body "Testing the plan automation"
```

4. Observez le workflow s'executer :

```bash
gh run list --workflow=terraform-plan.yml
gh run watch
```

5. Verifiez le commentaire automatique sur la PR :

```bash
gh pr view --web  # Ouvre la PR dans le navigateur
```

Vous devriez voir le plan Terraform en tant que commentaire automatique.

6. Modifiez le code Terraform et poussez a nouveau :

```bash
# Changement dans main.tf
git add labs/session-09-terraform-apps/solution/main.tf
git commit -m "Update terraform config"
git push origin feature-branch
```

Le workflow re-genere automatiquement le plan et met a jour le commentaire.

**Question** : Comment cette automatisation aide-t-elle lors du code review ? Quelles informations supplementaires ajouteriez-vous au commentaire (ex: estimations de cout) ?

---

## Bonus 2 : Smoke test post-deploiement avec auto-rollback (20 min)

Ajoutez une **etape de smoke test** qui valide le deploiement et **rollback automatiquement** en cas d'erreur :

1. Modifiez votre workflow de deploiement (ex: `.github/workflows/deploy.yml`) :

```yaml
name: Deploy to GKE

on:
  push:
    branches:
      - main

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure kubectl
        run: |
          gcloud container clusters get-credentials <VOTRE_PRENOM>-cluster \
            --zone europe-west9-a \
            --project cloud-447406

      - name: Build and push Docker image
        run: |
          docker build -t europe-west9-docker.pkg.dev/cloud-447406/training/api:latest -f app/api/Dockerfile.multistage app/api/
          docker push europe-west9-docker.pkg.dev/cloud-447406/training/api:latest

      - name: Deploy to GKE
        run: |
          kubectl set image deployment/api \
            -n exercices \
            api=europe-west9-docker.pkg.dev/cloud-447406/training/api:latest \
            --record

      - name: Wait for rollout
        run: |
          kubectl rollout status deployment/api -n exercices --timeout=5m

      - name: Smoke test - Health check
        id: health-check
        run: |
          # Attendre que les pods soient prets
          sleep 30
          
          # Test du health endpoint
          STATUS=$(kubectl exec deploy/frontend -n exercices -- \
            curl -s -o /dev/null -w "%{http_code}" \
            http://api.exercices.svc.cluster.local/health)
          
          echo "Health check HTTP status: $STATUS"
          
          if [ "$STATUS" = "200" ]; then
            echo "Smoke test PASSED"
            exit 0
          else
            echo "Smoke test FAILED (HTTP $STATUS)"
            exit 1
          fi

      - name: Rollback on failure
        if: failure()
        run: |
          echo "Deploiement echoue ! Rollback automatique..."
          kubectl rollout undo deployment/api -n exercices
          kubectl rollout status deployment/api -n exercices --timeout=5m
          exit 1
```

2. Committez et poussez :

```bash
git add .github/workflows/deploy.yml
git commit -m "ci: add smoke tests with auto-rollback"
git push origin main
```

3. Observez le workflow :

```bash
gh run watch
```

4. Testez le rollback en introduisant un bug (image inexistante) :

```bash
# Modifiez le Dockerfile ou le code pour creer une image qui ne demarre pas
git add .
git commit -m "test: introduce bug for rollback testing"
git push origin main
```

Le workflow devrait detecter l'erreur et faire un rollback automatique.

5. Verifiez que le pod precedent est bien restaure :

```bash
kubectl rollout history deployment/api -n exercices
kubectl get pods -n exercices -l app=api
```

**Question** : Quels autres tests incluiriez-vous dans un smoke test (ex: endpoints critiques, metriques, dependances) ? Comment eviter les faux positifs ?

---

## Bonus 3 : Matrix strategy pour multi-environnement (15 min)

Utilisez les **matrix strategies** pour tester et deployer dans plusieurs environnements en parallele :

1. Creez un workflow avec une matrix pour dev, staging et production :

```yaml
name: Multi-environment Deploy

on:
  push:
    branches:
      - main

jobs:
  deploy:
    strategy:
      matrix:
        environment:
          - name: dev
            cluster: dev-cluster
            zone: europe-west9-a
            namespace: dev
          - name: staging
            cluster: staging-cluster
            zone: europe-west9-a
            namespace: staging
          - name: production
            cluster: prod-cluster
            zone: europe-west9-a
            namespace: production
        
        # Optionnel : tester sur plusieurs versions
        api-version: [v1, v2]

    runs-on: ubuntu-latest
    environment: ${{ matrix.environment.name }}
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      - name: Configure kubectl for ${{ matrix.environment.name }}
        run: |
          gcloud container clusters get-credentials ${{ matrix.environment.cluster }} \
            --zone ${{ matrix.environment.zone }} \
            --project cloud-447406

      - name: Build and push Docker image (API v${{ matrix.api-version }})
        run: |
          docker build \
            -t europe-west9-docker.pkg.dev/cloud-447406/training/api:${{ matrix.environment.name }}-${{ matrix.api-version }} \
            --build-arg VERSION=${{ matrix.api-version }} \
            -f app/api/Dockerfile.multistage app/api/
          
          docker push europe-west9-docker.pkg.dev/cloud-447406/training/api:${{ matrix.environment.name }}-${{ matrix.api-version }}

      - name: Deploy to ${{ matrix.environment.name }}
        run: |
          kubectl set image deployment/api \
            -n ${{ matrix.environment.namespace }} \
            api=europe-west9-docker.pkg.dev/cloud-447406/training/api:${{ matrix.environment.name }}-${{ matrix.api-version }} \
            --record

      - name: Wait for rollout in ${{ matrix.environment.name }}
        run: |
          kubectl rollout status deployment/api \
            -n ${{ matrix.environment.namespace }} \
            --timeout=10m

      - name: Health check in ${{ matrix.environment.name }}
        run: |
          kubectl exec deploy/frontend -n ${{ matrix.environment.namespace }} -- \
            curl -s http://api.${{ matrix.environment.namespace }}.svc.cluster.local/health
```

2. Committez et poussez :

```bash
git add .github/workflows/multi-env-deploy.yml
git commit -m "ci: add multi-environment matrix strategy"
git push origin main
```

3. Observez le workflow dans GitHub Actions :

```bash
gh run list
gh run view <RUN_ID>
```

Vous devriez voir 6 jobs s'executer en parallele (3 environments x 2 api-versions).

4. Explorez les logs de chaque job :

```bash
gh run view <RUN_ID> --log
```

5. Testez les dependances (ex: deployer en prod uniquement apres staging OK) :

Modifiez le YAML pour ajouter des `needs` :

```yaml
deploy-prod:
  needs: deploy-staging
  if: success()
  # ... rest of job config
```

**Question** : Quels sont les avantages d'une matrix strategy ? Comment gerer les secrets differents par environnement ? Quand devriez-vous ajouter des approvals manuelles avant prod ?

---

## Bonus 4 : Notifications et alertes de deploiement (15 min)

Ajoutez des **notifications post-deploiement** pour alerter l'équipe via Slack ou email :

1. Creez un workflow qui envoie des notifications :

```yaml
name: Deploy with Notifications

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      # ... autres etapes de deploiement ...

      - name: Deploy status - Success
        if: success()
        uses: 8398a7/action-slack@v3
        with:
          status: success
          text: |
            Deploiement reussi sur production
            Commit: ${{ github.sha }}
            Branch: ${{ github.ref }}
            Author: ${{ github.actor }}
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
          fields: repo,message,commit,author

      - name: Deploy status - Failure
        if: failure()
        uses: 8398a7/action-slack@v3
        with:
          status: failure
          text: |
            Deploiement echoue sur production
            Commit: ${{ github.sha }}
            Branch: ${{ github.ref }}
            Error logs: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
          webhook_url: ${{ secrets.SLACK_WEBHOOK }}
          fields: repo,message,commit,author

      - name: Send email notification (success)
        if: success()
        uses: dawidd6/action-send-mail@v3
        with:
          server_address: ${{ secrets.EMAIL_SERVER }}
          server_port: ${{ secrets.EMAIL_PORT }}
          username: ${{ secrets.EMAIL_USERNAME }}
          password: ${{ secrets.EMAIL_PASSWORD }}
          subject: "Deploiement reussi - API v${{ github.sha }}"
          to: team@example.com
          from: ci@example.com
          body: |
            Deploiement reussi sur production !
            
            Commit: ${{ github.sha }}
            Branch: ${{ github.ref }}
            Author: ${{ github.actor }}
            
            Verifiez l'etat : ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

2. Configurez les secrets GitHub :

```bash
# Dans les settings de votre fork, ajoutez:
# SLACK_WEBHOOK: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
# EMAIL_SERVER, EMAIL_PORT, EMAIL_USERNAME, EMAIL_PASSWORD
```

3. Committez et poussez :

```bash
git add .github/workflows/deploy-with-notifications.yml
git commit -m "ci: add deployment notifications"
git push origin main
```

4. Observez les notifications dans Slack ou votre email apres deploiement :

```bash
gh run watch
```

5. (Optionnel) Ajoutez une notification manuelle pour les alertes critiques :

```yaml
- name: Notify PagerDuty on failure
  if: failure()
  run: |
    curl -X POST https://events.pagerduty.com/v2/enqueue \
      -H 'Content-Type: application/json' \
      -d '{
        "routing_key": "${{ secrets.PAGERDUTY_ROUTING_KEY }}",
        "event_action": "trigger",
        "dedup_key": "deploy-${{ github.run_id }}",
        "payload": {
          "summary": "Deploiement echoue sur production",
          "severity": "critical",
          "source": "GitHub Actions"
        }
      }'
```

**Question** : Quels autres outils de notification utiliseriez-vous en production (ex: Teams, Discord, Datadog) ? Comment eviter les notifications spam si un deploiement est retenté plusieurs fois ?
