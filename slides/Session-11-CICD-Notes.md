# Session 11 — CI/CD et Déploiement Multi-Environnement
## Notes du formateur (15 diapos)

> Notes extraites du deck, une diapo par section. C'est la **session finale** :
> on relie tout ce qu'on a vu (Docker, K8s, Terraform, production-readiness) dans
> un pipeline automatisé du commit à la prod.

---

## Diapo 1 — Formation Kubernetes (titre)

**ACCUEIL (5 min)**

- Session 10 : production-readiness (probes, HPA, PDB, NetworkPolicy, monitoring)
- Questions restées en suspens ?

**OBJECTIF DU JOUR — DU CODE À LA PRODUCTION, SANS CLIC MANUEL**

- Pipeline CI/CD complet avec GitHub Actions
- Build → push image → deploy sur GKE, automatiquement
- Authentification **sans clé** : Workload Identity Federation
- Stratégies de déploiement : Rolling, Blue-Green, Canary
- Et on clôture le parcours des 11 sessions

**TRANSITION**

- « Jusqu'ici on déployait à la main avec kubectl. Aujourd'hui, c'est git push → la machine fait le reste. »

---

## Diapo 2 — Agenda de la session

**PRÉSENTATION DE L'AGENDA**

- Recap S10, puis le cycle CI/CD (la vue d'ensemble)
- GitHub Actions : la mécanique (workflows, jobs, steps, WIF)
- Multi-environnement : staging vs production
- Stratégies de déploiement : quand utiliser quoi
- Walkthrough des vrais pipelines RFLKT (staging.yml / prod.yml)
- Démo live + clôture des 11 sessions
- ~1h de TP : chacun construit et déclenche son propre pipeline

---

## Diapo 3 — Recap Session 10 : Production-Ready

**INTERACTION (3 min)**

- Qu'est-ce qui rend une app « production-ready » ? (probes, resources, HPA, monitoring)
- Probes : différence liveness / readiness ?
- Pourquoi des requests sont indispensables au HPA ?

**TRANSITION**

- « On a une app robuste. Mais qui la déploie, et comment, quand on push du code ? C'est le sujet du jour. »

---

## Diapo 4 — Le cycle CI/CD : de la source à la production

**EXPLICATION (8 min) — LA VUE D'ENSEMBLE**

- 6 étapes : Code → Build → Test → Push → Deploy → Monitor
- **Code** : push sur main, feature branches, PR
- **Build** : `docker build` — et c'est ici que le multi-stage entre en jeu
- **Test** : unit / integration / scan d'image (sécurité)
- **Push** : image taguée et poussée vers un registry (Artifact Registry)
- **Deploy** : `kubectl set image` / `apply` → rolling update
- **Monitor** : health checks, alerting, rollback si besoin

**POINT CLÉ**

- CI (Continuous Integration) = build + test à chaque commit
- CD (Continuous Delivery/Deployment) = déploiement automatique
- L'objectif : chaque commit sur main = candidat déployable, sans intervention manuelle

---

## Diapo 5 — GitHub Actions : structure d'un workflow

**EXPLICATION (8 min)**

- `name` : identifiant du workflow
- `on:` les déclencheurs — push, pull_request, schedule (cron), workflow_dispatch (manuel)
- `jobs` : ensemble de jobs (parallèles par défaut ; `needs:` pour enchaîner)
- `runs-on` : le runner (ubuntu-latest)
- `steps` : suite d'étapes — `uses:` (action réutilisable) ou `run:` (commande shell)

**WORKLOAD IDENTITY FEDERATION — LE POINT IMPORTANT**

- Auth historique : une **clé de service JSON** stockée en secret → fuite = compromission durable
- WIF : GitHub présente un **token OIDC** de courte durée, GCP le vérifie et émet un token temporaire
- Pas de clé en clair, pas de rotation à gérer
- `permissions: id-token: write` est requis côté job pour que GitHub émette le token OIDC

**DANS LE TP**

- Le formateur a créé une fois : le provider WIF + le SA `training-deployer`
- Le provider accepte **tout fork nommé `k8s-training`** → mêmes deux secrets pour toute la classe

---

## Diapo 6 — GitHub Actions n'est qu'un outil — le paysage CI/CD

**MISE EN PERSPECTIVE (4 min)**

- Question fréquente : « pourquoi GitHub Actions et pas un autre ? »
- Le concept est universel : un pipeline déclaratif déclenché par un événement Git. L'outil change, le principe reste.

**LE PAYSAGE**

- **Jenkins** : le vétéran, self-hosted, ultra-extensible (plugins), pipelines Groovy — puissant mais lourd à maintenir
- **GitLab CI/CD** : intégré au repo GitLab (`.gitlab-ci.yml` + runners), repo + CI + registry tout-en-un
- **CircleCI / Travis / Drone** : SaaS, config YAML, démarrage rapide
- **Argo CD / Flux** : GitOps pull-based — le cluster réconcilie depuis Git (cf. diapo GitOps)
- **Tekton** : pipelines natifs Kubernetes (CRDs), brique de base de nombreuses plateformes
- **Ansible** : plutôt config management / provisioning, parfois utilisé pour orchestrer un déploiement

**POURQUOI GITHUB ACTIONS POUR LA FORMATION**

- Le code est déjà sur GitHub : aucune infra CI à installer, gratuit, marketplace d'actions riche
- Ce qu'on apprend (jobs, steps, secrets, WIF) se transpose tel quel aux autres outils

---

## Diapo 7 — Dockerfile multi-stage : optimiser les images

**EXPLICATION (7 min)**

- Single-stage : l'image finale contient le compilateur Go, les outils de build, etc. (~850 Mo)
- Multi-stage : on compile dans un stage `builder`, puis on copie **juste le binaire** dans une image `scratch` (vide) → ~15 Mo
- Bénéfices : image 50× plus petite, pull plus rapide, surface d'attaque réduite (pas de shell, pas de package manager)

**DÉTAILS QUI COMPTENT**

- `CGO_ENABLED=0` : binaire statique, indispensable pour tourner sur `scratch`
- On copie les `ca-certificates` depuis le builder pour les appels HTTPS sortants
- `scratch` = aucun OS : pas de `sh`, pas de `curl` → on debugge autrement (logs, ephemeral containers)

**DANS LE TP**

- Étape 2 : comparer `docker images` entre `Dockerfile` et `Dockerfile.multistage`
- Le pipeline build toujours avec `Dockerfile.multistage`

---

## Diapo 8 — Stratégies de déploiement

**EXPLICATION (8 min)**

- **Rolling Update (défaut K8s)** : remplace les pods progressivement (1 nouveau, 1 ancien retiré). Zéro downtime, rollback facile. 95 % des cas.
- **Blue-Green** : deux versions complètes côte à côte, bascule instantanée. Double les ressources mais rollback immédiat. Pour les changements majeurs / tests avant bascule.
- **Canary** : on envoie un petit % du trafic vers v2, on observe les métriques, puis on monte. Avec Traefik = weighted routing. Pour les changements critiques / A/B testing.

**À RETENIR**

- Choisir selon le **risque** et la **tolérance au downtime**
- Le rolling update K8s s'appuie sur les **readinessProbes** (vu en S10) pour le zéro downtime

---

## Diapo 9 — GitOps : Source of Truth = Git

**EXPLICATION (6 min)**

- **Push-based** (GitHub Actions) : le pipeline pousse vers le cluster (`kubectl apply`). Simple, familier, rapide. C'est ce qu'on fait dans le TP.
- **Pull-based** (ArgoCD / Flux) : un agent dans le cluster surveille le repo Git et réconcilie en continu. Audit complet, détection de drift (réalité ≠ Git), réconciliation automatique.
- RFLKT utilise : GitHub Actions (push-based) + Terraform (IaC)

**TRANSITION**

- « Git devient la source de vérité. Le déploiement n'est qu'une conséquence d'un merge. »

---

## Diapo 10 — Multi-environnement : Staging et Production

**EXPLICATION (6 min)**

- Feature branch → PR (code review + tests) → merge sur main
- **Staging (auto)** : chaque push sur main → déploiement automatique. Test rapide, environnement jetable.
- **Production (manuel)** : déclenchée par un **git tag** (`v1.2.3`) créé intentionnellement. Déploiement = release officielle.

**À RETENIR**

- L'auto-deploy en staging accélère le feedback ; la prod garde une barrière humaine (tag / approval)
- Secrets différents par environnement, approvals manuelles avant prod (environment + required reviewers)

---

## Diapo 11 — Walkthrough : les pipelines RFLKT réels

**DÉMO / LECTURE DE CODE (8 min)**

- Ouvrir `.github/workflows/staging.yml` et `prod.yml` du repo `cloud-infrastructure`
- **Staging** : push main → auth → terraform init/plan/apply (CRDs, NEGs) → vérif backend → deploy apps
- **Production** : déclenché par release/tag → build image → tests d'intégration → push Artifact Registry → terraform apply (infra prod) → deploy → smoke tests
- **Key** : Terraform gère l'infra, GitHub Actions gère le CI/CD, WIF gère l'auth

**HONNÊTETÉ TECHNIQUE**

- En vrai, RFLKT utilise encore une clé de service pour ces pipelines infra ; WIF est le standard cible et ce que les stagiaires mettent en place dans le TP (keyless dès le départ).

---

## Diapo 12 — Comparaison : GKE, EKS, AKS

**EXPLICATION (5 min)**

- **GKE (Google)** : Autopilot (nodes managés), release channels, control plane gratuit, Anthos. Startups / expérience managée.
- **EKS (AWS)** : Fargate (pods serverless), IRSA (IAM fin), VPC CNI. Entreprises déjà sur AWS.
- **AKS (Azure)** : intégration Azure AD, control plane gratuit, spot VMs. Boutiques Microsoft.

**BOTTOM LINE**

- Kubernetes reste Kubernetes : le code (YAML) est portable. Le choix dépend surtout des **coûts** et de l'**écosystème existant**.

---

## Diapo 13 — Architecture du TP — Déploiement sur GKE

**LANCEMENT DU TP (5 min)**

- Flux : `git push main` → GitHub Actions → build/push image → `kubectl set image` dans **votre namespace trainee-NN**
- Auth : WIF (token OIDC → impersonation du SA `training-deployer`)
- Cluster **partagé** : on reste dans son namespace, comme en S9/S10

**ÉTAPES DU TP (~1h)**

**1. Forker le repo + configurer les 2 secrets (WIF provider + SA, fournis par le formateur)**

**2. Comparer les tailles d'image (single vs multi-stage)**

**3. Mettre `NAMESPACE: trainee-NN` puis compléter les TODOs de `deploy.yml`**

**4. git push → observer le workflow (gh run watch) → vérifier le rollout**

**5. Provoquer un bug (image inexistante) → `kubectl rollout undo`**

**BONUS**

- terraform plan en commentaire de PR ; smoke test + auto-rollback ; matrix multi-env ; notifications Slack

**PIÈGES À RAPPELER**

- Le cluster est **zonal** : `europe-west9-b`, pas la région
- Le pod `frontend` (nginx) n'a **pas `curl`** → utiliser `wget` dans le smoke test
- Le dépôt Artifact Registry est **partagé** → tag préfixé par le namespace pour éviter les collisions

---

## Diapo 14 — Démo Live — CI/CD en action

**DÉMO LIVE (10-15 min)**

1. Montrer l'onglet **Actions** du fork (exécutions, logs, status)
2. Déclencher un deploy volontaire (`git push` sur main)
3. Suivre le build Docker dans les logs (build → push registry)
4. Voir l'étape deploy (`kubectl set image`, rolling update lancé)
5. `kubectl get pods -n trainee-NN -w` → anciens pods terminent, nouveaux démarrent
6. Vérifier la santé (readinessProbe → pods Ready)
7. Tester le service → le nouveau code est en prod

**TIMING**

- ~10-15 min en temps réel ; pendant le build, expliquer ce qui se passe

---

## Diapo 15 — Récap Final — Votre parcours en 11 sessions

**CLÔTURE (5 min)**

- S1-S2 : Pods, Services, DNS — S3 : Ingress/Traefik — S4 : Storage — S5 : ConfigMaps/Secrets — S6 : Secrets avancés — S7-S9 : Terraform/GKE — S10 : Probes/HPA/PDB — S11 : CI/CD (vous êtes ici)

**LES 4 GRANDS TAKEAWAYS**

1. **Déclaratif > Impératif** : on décrit l'état souhaité (YAML), K8s s'occupe du détail
2. **Infrastructure as Code** : Terraform = infra versionnée, auditable, reproductible
3. **Automatisation totale** : CI/CD = du commit à la prod sans clic manuel, zéro downtime
4. **Résilience par design** : probes, HPA, PDB, monitoring → l'app survit aux pannes

**MOT DE LA FIN**

- « Vous êtes prêts pour la production. » Questions, retours, et pistes pour aller plus loin (ArgoCD, service mesh, observabilité avancée).
