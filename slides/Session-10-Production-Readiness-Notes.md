# Session 10 — Production Readiness
## Notes du formateur (16 diapos)

> Notes extraites du deck, une diapo par section.

---

## Diapo 1 — Formation Kubernetes

**ACCUEIL (5 min)**

- Session 9 : Terraform pour la gestion d'infrastructure GKE
- Questions sur les Modules Terraform ?

**OBJECTIF DU JOUR — PRÉPARER LA PRODUCTION**

- Comprendre les Health Probes : liveness, readiness, startup
- Gérer les ressources : requests, limits, QoS classes
- Autoscaler : HPA, VPA, Cluster Autoscaler
- Résilience : PodDisruptionBudget, zero-downtime deployments
- Sécurité : NetworkPolicy, RBAC, Pod Security Standards
- Monitoring : les 3 piliers (Logs, Metrics, Traces)
- Voir comment tout s'assemble dans l'application de formation

**TRANSITION**

- "On a vu comment déployer sur Kubernetes. Maintenant, c'est comment garder ça stable, rapide et sécurisé en prod."

---

## Diapo 2 — Agenda de la session

**PRÉSENTATION DE L'AGENDA**

- Production Readiness = c'est pas juste 'ça marche', c'est 'ça tient la charge, ça se remet des pannes, ça reste sécurisé'
- On commence par la santé des pods
- Puis on parle ressources : pas trop utiliser le cluster
- Ensuite l'autoscaling : quand ça monte en charge
- Et enfin résilience & sécurité : protection contre les pannes et les attaques
- 1h30 de TP pour appliquer tout ça

---

## Diapo 3 — Recap — Session 9

**INTERACTION (3 min)**

- Demander aux participants : qu'est-ce qu'on a fait en S9 ?
- Terraform : quel avantage par rapport à kubectl apply ?
- Module application/ : quand on le réutilise pour 10 microservices, qu'est-ce qu'on gagne ?

**TRANSITION**

- "Le Terraform nous donne les ressources. Mais Y A T-IL un pod en train de crasher ?

**  Ça répond bien aux requêtes ? Les limites de ressources, c'est quoi ?**

**  Si je charge le cluster, ça scale automatiquement ?**

**  Voilà ce qu'on voit aujourd'hui."**

---

## Diapo 4 — Health Probes — Les trois piliers

**EXPLICATION (10 min) — IMPORTANT**

- Liveness : 'est-ce que le processus tourne ?' → /health (juste ping, pas de dépendances)

**  Si c'est faux, K8s tue le pod et le redémarre**

- Readiness : 'peut-il recevoir du trafic ?' → /ready (peut inclure les dépendances)

**  Si c'est faux, le Service retire le pod du load-balancer**

**  Important : pendant un déploiement rolling, les anciens pods deviennent not-ready**

**  → zéro downtime si configured correctement**

- Startup : 'il est en train de démarrer' → donne du temps avant liveness

**  Utile pour les apps lentes à bootstrap**

**⚠️ PIÈGE COURANT — LIVENESS + DÉPENDANCES**

- Si /health check la DB et la DB est down : le pod redémarre infiniment
- Cascading failures : 1 service down → tout le reste redémarre → pire que rien
- Bonne pratique : /health = 'juste moi', /ready = 'moi + les dépendances que j'ai besoin'

**DANS LE TP**

- L'API Go a déjà les endpoints /health et /ready
- On va configurer les probes dans le Deployment
- Puis on va simuler un crash et voir comment K8s le gère

---

## Diapo 5 — Health Probes — Configuration YAML

**EXPLICATION (5 min)**

- httpGet : type de probe (aussi: exec, tcpSocket)
- initialDelaySeconds : délai avant le premier check

**  Utile pour les apps qui mettent du temps à démarrer**

- periodSeconds : intervalle entre les checks
- failureThreshold : nombre de checks échoués avant action

**  Liveness : après 3 échecs → restart**

**  Readiness : après 1 échec → removed from service**

**BONNES PRATIQUES**

- readinessProbe plus "loose" que liveness
- Startup : utilisé seulement si l'app a besoin de >30s pour démarrer
- exec probe : pour les apps sans HTTP (scripts, etc.)

---

## Diapo 6 — Resource Management — Requests vs Limits

**EXPLICATION (10 min) — CRUCIAL POUR LE SCHEDULING**

- Requests : ce que le scheduler utilise pour placer le pod

**  "J'ai besoin de 500m CPU et 256Mi RAM"**

**  Scheduler regarde : avez-vous des nodes avec 500m libres ?**

**  Si non : pod reste en Pending**

- Limits : ce que cgroup enforce. Dépasser = SIGKILL

**  Important : requests <= limits**

**QOS CLASSES — ORDRE D'ÉVICTION**

- Guaranteed : plus prioritaire, jamais évicté sauf si requests > disponible

**  "requests = limits" → garantis de ressources**

- Burstable : niveau intermédiaire, évicté après Guaranteed

**  Peut utiliser plus que requests mais moins que limits**

- BestEffort : aucune garantie, premiers évictés quand cluster saturé

**  Utile pour les jobs batch, les tests**

**ERREUR COURANTE**

- Mettre limits trop bas → pod tue en permanence
- Mettre requests = 0 → pod peut aller n'importe où, Eviction disasters
- La solution : identifier les vrais besoins (faire un benchmark)

---

## Diapo 7 — HPA — Horizontal Pod Autoscaler

**EXPLICATION (10 min)**

- HPA = ScalingController qui watch les métriques et ajuste replicas
- Cycle: lire métriques → comparer à target → si CPU > 70%, scale up → créer pod
- minReplicas : pas en dessous (au moins 2 pour la HA)
- maxReplicas : pas au-dessus (coûts, limites cluster)
- averageUtilization : moyenne sur tous les pods actuels

**SCALING ALGORITHM**

- replicasNeeded = ceil(currentMetric / targetMetric × currentReplicas)
- Ex: 4 pods à 90% CPU, target 70% = 4 × (90/70) = 5.14 → 6 pods
- Cooldown : après scale-up, attendre 3 min avant de recheck

**  → Évite les cascades**

- Scale-down plus conservateur : attend plus longtemps

**⚠️ PRÉREQUIS**

- metrics-server doit être installé
- Les pods doivent avoir des REQUESTS (pour calculer l'utilisation %)
- Sans requests, HPA regarde les valeurs absolues en CPU → moins fiable

**PIÈGES**

- Cache: les métriques ne sont pas en temps réel (15s de lag)
- Cooldown : si on scale trop souvent, on rate les vrais spikes
- Thrashing : min/max trop proches → peut osciller
- Custom metrics : plus complexe, requiert Prometheus + adapter

---

## Diapo 8 — VPA & Cluster Autoscaler — 3-tier scaling

**EXPLICATION (10 min)**

- Trois niveaux d'autoscaling travaillent ensemble
- HPA : 'j'ai besoin de plus de capacity' → create pods
- VPA : 'les pods ont des requests mal calibrés' → adjust up/down
- Cluster Autoscaler : 'les pods ne fit sur aucun node' → add nodes

**VPA (Vertical Pod Autoscaler)**

- Analyse l'historique d'utilisation
- Recommande des requests/limits optimaux
- Modes: Auto (kill+restart), Recreate, Off
- ⚠️ Ne pas combiner VPA + HPA sur le même metric (CPU) → instabilité
- Utilisé généralement en 'Recommendation Mode' = just advise, pas auto-apply

**CLUSTER AUTOSCALER**

- Automatique avec GKE (Autoscaling node pool)
- Watch : pod en Pending → trouve un node compatible → demande un node
- Scale-down : node vide depuis 10 min → drain → supprime
- Important : compatible avec HPA, pas en conflit

**DANS LA PRATIQUE RFLKT**

- GKE a Cluster Autoscaler built-in
- HPA active sur l'API et le frontend
- VPA en recommendation mode = on consulte les suggestions periodiquement

---

## Diapo 9 — Scaling — quand le HPA ne suffit pas

**SCALING AU-DELÀ DU HPA (5 min)**

- Le HPA augmente le nombre de pods — il ne crée PAS de capacité.
- Si aucun nœud n'a de place : pods Pending (Unschedulable).
- Cluster Autoscaler (GKE) ajoute des nœuds, borné par max-nodes + quota régional.
- Karpenter : provisioning just-in-time, choix d'instance, consolidation, spot natif — souvent plus rapide et moins cher que le CA.
- Spot/Preemptible : grosse économie mais interruptions -> PDB + terminationGracePeriod + arrêt propre.
- Le cluster de formation tourne déjà sur des nœuds e2 spot.

---

## Diapo 10 — PodDisruptionBudget — Zéro downtime

**EXPLICATION (8 min)**

- PDB = 'Je veux que vous me laissiez au moins N pods up pendant la maintenance'
- K8s respecte ce budget = zéro downtime deployment

**minAvailable vs maxUnavailable**

- minAvailable: 1 = 'garde ≥1 pod available'

**  Avec 3 replicas : K8s peut drain 2**

- maxUnavailable: 1 = 'autorise au max 1 pod down'

**  Avec 3 replicas : idem résultat**

- Les deux sont équivalents, c'est une préférence

**⚠️ PDB NE PROTÈGE PAS CONTRE**

- Les crashes des pods (liveness probe redémarrage)
- Les OOM kills
- Les exécutions de kubectl delete pod (intentionnel)
- PDB c'est pour les disruptions volontaires / volontaires du cluster

**DANS LE TP**

- On ajoute une PDB à l'API
- Puis on simule un node drain et on observe que ≥1 pod reste up

---

## Diapo 11 — NetworkPolicy — Segmentation réseau

**EXPLICATION (8 min)**

- NetworkPolicy = firewall K8s
- Défaut : tous les pods communiquent librement (north-south)
- Avec policy : deny all (implicite), puis allowlist des routes

**ANATOMIE**

- podSelector : quels pods cette policy protège
- policyTypes : Ingress (trafic entrant), Egress (sortant)
- ingress/egress : règles avec from/to

**  from.podSelector : pods autorisés à envoyer**

**  ports : quels ports/protocoles**

**EXEMPLE RFLKT**

- API : ingress seulement du frontend + prometheus scrape
- Frontend : ingress du monde extérieur (Traefik)
- DB : ingress seulement de l'API
- Chaque micro-service = son propre NetworkPolicy

**⚠️ IMPORTANT**

- NetworkPolicy requiert un CNI qui support ça (Calico, Cilium, etc.)
- GKE default n'a pas de NetworkPolicy support → faut Dataplane v2
- Sans support, la policy est créée mais IGNORÉE = pas de protection

---

## Diapo 12 — Observabilité — Les 3 piliers

**EXPLICATION (10 min)**

- 3 piliers = le triptyque de l'observabilité
- Logs : incident happened? check logs
- Metrics : is it healthy? CPU trending up? Latency increasing?
- Traces : where did it slow down? Which service?

**LOGS**

- Chaque pod stdout/stderr → collected par K8s
- kubectl logs pod, ou centralisé (ELK, Loki, CloudLogging)
- Importantes : les exceptions, les errors, warnings

**METRICS**

- Prometheus scrape les pods toutes les 15s
- Grafana visualise les métriques en dashboards
- Alerting : si CPU > 80%, notifier ops
- GKE Cloud Monitoring = équivalent GCP

**TRACES**

- Une requête HTTP traverse: Traefik → API → DB
- Chaque hop = span, tous liés par trace ID
- Identifie les bottlenecks (slow query? slow API call?)

**DANS LE TP**

- On va installer prometheus + grafana
- Créer un dashboard basique pour l'API

---

## Diapo 13 — Architecture du TP — Toutes les briques

**LANCEMENT DU TP (5 min)**

- Recap des fichiers du TP : starter/ et solution/
- Participants travaillent par pair
- Formateur circule et aide

**ÉTAPES DU TP**

**1. Ajouter livenessProbe + readinessProbe au Deployment API**

**2. Ajouter requests/limits + comprendre QoS**

**3. Créer une HPA, voir les pods scale quand CPU monte**

**4. PDB : minAvailable: 1, puis simulator drain**

**5. NetworkPolicy : Deny all, puis Ingress API from frontend**

**6. Prometheus + Grafana : scraper les metrics de l'API**

**BONUS**

- Load test: hey -n 1000 -c 50 http://api:8080/items
- Watch HPA: watch kubectl get hpa
- Crash un pod: kubectl delete pod api-xxx
- Voir readinessProbe récupérer

---

## Diapo 14 — Le module application/ — le code réel (cloud-infrastructure)

**DÉMO LIVE (10 min)**

- Ouvrir le code du module application/ dans RFLKT

**  → Montrer les probes, les resources, les HPA labels**

- Ouvrir GCP Console → Cloud Monitoring

**  → Montrer un dashboard : CPU, RAM, requêtes/sec, errors**

- kubectl get hpa -w

**  → Pendant qu'on charge: hey -n 10000 -c 50**

**  → Montrer le scale-up en temps réel**

- kubectl get networkpolicies

**  → Vérifier que deny-all est là**

- Crash un pod

**  → Montrer que readinessProbe l'retire du service**

**  → Restart automatique via liveness**

**KEY TAKEAWAYS**

- Production readiness = probes + resources + scaling + resilience + security
- Pas juste 'ça marche', c'est 'ça tient la charge, ça se remet des pannes'
- Le module application/ = l'abstraction qui encapsule tout

---

## Diapo 15 — Do's & Don'ts — Production Readiness

**DO'S & DON'TS (5 min)**

- requests : sans eux, pas de HPA et éviction prioritaire (BestEffort).
- liveness != readiness : liveness ne doit JAMAIS dépendre d'une dépendance externe (DB) sinon restart loop.
- limits trop bas = OOMKilled ; limits == requests = QoS Guaranteed (utile pour le critique).
- HPA et VPA sur la même métrique se battent : VPA en mode Off (reco) si HPA actif.
- NetworkPolicy sans CNI qui l'applique (Dataplane V2 / Calico) = silencieusement sans effet.
- Toujours un PDB avant un drain / upgrade.

---

## Diapo 16 — Récapitulatif & Mini-défi

**CLÔTURE (5 min)**

- Résumer les 4 piliers de la production readiness
- Rappeler : tout s'encapsule dans le module application/
- Questions des participants ?

**PROCHAINES ÉTAPES (SESSIONS 11)**

- CI/CD : GitHub Actions, automatic deployment
- Deployment patterns : Blue-Green, Canary
- Monitoring alerting : PagerDuty, oncall rotation

**MINI-DÉFI**

- Pour ceux qui finissent le TP avant la fin
- VPA est optionnel, complexe, mais intéressant
- Les recommendations peuvent surprendre (requests trop élevées ?)
