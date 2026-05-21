# Session 6 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.
> Pensez a remplacer `<NOM>` par votre prenom dans tous les fichiers YAML et commandes.

> **Note** : sur le cluster partage, les trainees ne peuvent pas creer de namespaces ni de Service Accounts GCP. Certains exercices supposent que le formateur a deja prepare l'environnement (indique le cas echeant).

---

## Bonus 1 : ExternalSecret avec template et format custom (15 min)

ESO permet de **transformer** la structure du Secret K8s genere via la section `template`. Utile quand l'application attend un format specifique : `kubernetes.io/dockerconfigjson` pour un imagePullSecret, un fichier `.env`, du JSON, du YAML, etc.

Creez un `ExternalSecret` qui combine trois secrets GCP en un fichier `.env` materialise comme cle unique :

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

**Pour aller plus loin** : modifiez le `template` pour generer un `type: kubernetes.io/dockerconfigjson` (format imagePullSecret de Docker). Le `template.data` devra contenir une cle `.dockerconfigjson` avec la structure JSON attendue par Kubernetes (`{ "auths": { "<registry>": { "auth": "<base64(user:pass)>" }}}`).

**Question** : Quel est l'avantage d'un Secret materialise en `.env` plutot qu'en cles separees ? Citez un cas d'usage reel.

---

## Bonus 2 : Pin de version vs `:latest` -- rotation safe (20 min)

> **Suite directe** de la question ouverte du Bonus 2 de Session 5 (*"comment gerer les rotations de secrets critiques sans downtime ?"*). En CSI, vous aviez observe que `gcloud secrets versions add` modifie la valeur dans le fichier monte presque immediatement. En ESO, c'est encore plus rapide (le Secret K8s est mis a jour). Bien -- mais en prod, c'est exactement ce qu'on veut **eviter** sans controle.

Par defaut, ESO recupere `versions/latest` du secret GCP. **Probleme en prod** : une nouvelle version (potentiellement cassee) est propagee a tous les pods en moins d'une minute, sans canary, sans review. La parade : pinner une version specifique et bump via Pull Request.

### Etape 1 : Creer deux ExternalSecrets cote a cote

```yaml
# es-pinned.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: api-secret-pinned-<NOM>
  namespace: exercices
spec:
  refreshInterval: 30s
  secretStoreRef:
    name: gcp-secret-store-<NOM>
    kind: SecretStore
  target:
    name: api-secret-pinned-<NOM>
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: training-db-password
        version: "1"          # <-- PIN sur la version 1
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: api-secret-latest-<NOM>
  namespace: exercices
spec:
  refreshInterval: 30s
  secretStoreRef:
    name: gcp-secret-store-<NOM>
    kind: SecretStore
  target:
    name: api-secret-latest-<NOM>
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: training-db-password   # <-- pas de version => latest
```

```bash
kubectl apply -f es-pinned.yaml
```

### Etape 2 : Comparer les deux valeurs

```bash
kubectl get secret api-secret-pinned-<NOM> -n exercices \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d ; echo
kubectl get secret api-secret-latest-<NOM> -n exercices \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 -d ; echo
```

Tant que la version 1 est la plus recente, les deux valeurs sont identiques.

### Etape 3 : Le formateur publie une version 2

Demandez au formateur de faire `gcloud secrets versions add training-db-password --data-file=...`. Attendez 30s puis relancez les deux commandes :

- `api-secret-pinned-<NOM>` -> garde l'ancienne valeur (version 1)
- `api-secret-latest-<NOM>` -> a deja basculee sur la version 2

**Pourquoi c'est important en prod** :
- Le pin permet de **valider** la nouvelle version sur un environnement de staging avant de bump le numero en prod
- En cas d'incident, le rollback est un simple `kubectl apply` avec l'ancien numero (vs `gcloud secrets versions destroy` qui est destructeur)
- Argo CD / Flux gerent la diff version par version

**Question** : Comment automatiser le bump du numero de version dans un workflow GitOps ? Quels signaux declenchent le bump (rotation calendaire, alerte de compromission, deploiement) ?

---

## Bonus 3 : Pieges destructeurs -- cascade delete et overwrite (15 min)

**Demos a faire dans votre propre namespace uniquement**. Deux comportements qui ont casse des prods reelles.

### Etape 1 : Le cascade delete (deja vu a l'Etape 6, observe a froid ici)

Creez un Deployment qui depend du Secret synchronise :

```bash
# api est deja deploye depuis l'etape 4, on l'utilise
kubectl get pods -n exercices -l app=api-<NOM>
```

Supprimez l'ExternalSecret :

```bash
kubectl delete externalsecret api-secrets-<NOM> -n exercices
kubectl get secret api-secrets-<NOM> -n exercices
# NotFound -- le Secret K8s a ete garbage-collected
```

Forcez un redemarrage du pod pour voir l'impact :

```bash
kubectl rollout restart deploy/api-<NOM> -n exercices
kubectl get pods -n exercices -l app=api-<NOM>
# CreateContainerConfigError -- le Secret reference n'existe plus
```

Recreez tout pour la suite :

```bash
kubectl apply -f ../starter/external-secret.yaml
sleep 5
kubectl rollout restart deploy/api-<NOM> -n exercices
```

### Etape 2 : Le piege de l'overwrite (issue ESO #4548)

Creez **manuellement** un Secret avec deux cles (simulant un Secret legacy avec plusieurs configs) :

```bash
kubectl create secret generic legacy-config-<NOM> -n exercices \
  --from-literal=OAUTH_TOKEN_LEGACY=do-not-lose-me \
  --from-literal=OTHER_KEY=important-value
```

Verifiez qu'il contient bien deux cles :

```bash
kubectl get secret legacy-config-<NOM> -n exercices -o jsonpath='{.data}' | jq 'keys'
```

Creez maintenant un ExternalSecret qui pointe vers le **meme nom** avec `creationPolicy: Owner` mais ne synchronise qu'**une** cle :

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: legacy-config-<NOM>
  namespace: exercices
spec:
  refreshInterval: 30s
  secretStoreRef:
    name: gcp-secret-store-<NOM>
    kind: SecretStore
  target:
    name: legacy-config-<NOM>   # <-- meme nom que le Secret existant
    creationPolicy: Owner
  data:
    - secretKey: OAUTH_TOKEN
      remoteRef:
        key: training-oauth-token
```

Appliquez et attendez 30s puis :

```bash
kubectl get secret legacy-config-<NOM> -n exercices -o jsonpath='{.data}' | jq 'keys'
# Resultat : ["OAUTH_TOKEN"] uniquement -- OAUTH_TOKEN_LEGACY et OTHER_KEY ont disparu !
```

**Lecon** : un `creationPolicy: Owner` doit toujours pointer vers un Secret **qu'il cree lui-meme**, jamais vers un Secret prexistant. Si vous devez **completer** un Secret existant, utilisez `creationPolicy: Merge`.

Nettoyage :

```bash
kubectl delete externalsecret legacy-config-<NOM> -n exercices
kubectl delete secret legacy-config-<NOM> -n exercices --ignore-not-found
```

**Question** : Quel garde-fou mettriez-vous en place dans votre process (review, policy OPA/Kyverno, naming convention) pour eviter qu'un dev cree un ExternalSecret qui ecrase `argocd-secret`, `cert-manager-webhook-ca` ou un autre Secret critique ?

---

## Bonus 4 : Diagnostic d'un ExternalSecret en panne (15 min)

En prod, un ExternalSecret peut tomber pour des dizaines de raisons. Apprenez l'arbre de diagnostic.

### Etape 1 : Provoquer une erreur (secret GCP inexistant)

Modifiez votre ExternalSecret pour pointer vers un secret qui n'existe pas :

```yaml
data:
  - secretKey: BAD
    remoteRef:
      key: training-does-not-exist
```

```bash
kubectl apply -f es-broken.yaml
sleep 5
kubectl get externalsecret api-secrets-<NOM> -n exercices
# STATUS doit afficher SecretSyncedError
```

### Etape 2 : Lire le status conditions (toujours commencer ici)

```bash
kubectl get externalsecret api-secrets-<NOM> -n exercices \
  -o jsonpath='{.status.conditions}' | jq .
```

Vous verrez quelque chose comme :
```json
[{
  "type": "Ready",
  "status": "False",
  "reason": "SecretSyncedError",
  "message": "could not get secret data from provider: ... NotFound"
}]
```

### Etape 3 : Lire les events du namespace

```bash
kubectl get events -n exercices --sort-by=.lastTimestamp \
  --field-selector involvedObject.name=api-secrets-<NOM>
```

### Etape 4 : Logs du controleur ESO

```bash
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets \
  --tail=100 | grep -i "<NOM>"
```

### Etape 5 : Arbre de diagnostic des erreurs courantes

| Symptome | Cause probable | Verification |
|----------|----------------|--------------|
| `NotFound` | Mauvais nom GCP | `gcloud secrets list \| grep training-` |
| `PermissionDenied` | IAM manquante | Verifier que la GCP SA a `secretmanager.secretAccessor` sur le projet |
| `failed to get token` | Workload Identity casse | KSA annotation `iam.gke.io/gcp-service-account` ? Binding `roles/iam.workloadIdentityUser` ? Metadata server joignable depuis le node ? |
| `SecretStore is not ready` | SecretStore en erreur | `kubectl describe secretstore gcp-secret-store-<NOM>` |
| `context deadline exceeded` | Reseau / Cloud NAT | Connectivite du noeud vers `secretmanager.googleapis.com` |
| Status `Ready` mais valeur ancienne | Cache cote app | L'app n'a pas relu (env var) -> `kubectl rollout restart` ou Reloader |

### Etape 6 : Signaux pour Prometheus / alerting

ESO expose les metriques suivantes (port `8080`/metrics du controleur) :

- `externalsecret_status_condition{condition="Ready",status="False"}` -> au moins un ES en erreur
- `externalsecret_sync_calls_error_total` -> taux d'erreurs de sync
- `externalsecret_provider_api_calls_count` -> volume d'appels (quota GCP, cost)
- `controller_runtime_reconcile_errors_total` -> erreurs du controleur lui-meme

**Question** : Concevez une PromQL/alert : "alerte si un ExternalSecret n'a pas reussi a sync depuis plus de 10 minutes". Quel SLO mettriez-vous sur la fraicheur des secrets ?

Restaurez l'ExternalSecret correct apres le test :

```bash
kubectl apply -f ../starter/external-secret.yaml
```

---

## Bonus 5 : ClusterSecretStore, multi-tenancy et bridge vers Vault (15 min)

> **Important** : la creation d'un ClusterSecretStore necessite des permissions cluster-admin que les trainees n'ont pas. Cet exercice est conceptuel.

### Partie 1 : ClusterSecretStore -- avantages et risques

Un `ClusterSecretStore` est un `SecretStore` cluster-scoped : un seul objet utilisable depuis n'importe quel namespace.

Avantages :
- Un seul point de configuration pour tous les namespaces
- Pas besoin de dupliquer la config provider
- Le ServiceAccount K8s reference peut etre dans un namespace dedie (ex : `external-secrets`)

Risques :
- **ESO ne limite pas quelles cles un namespace peut lire** via le store. Tous les devs avec la permission de creer un ExternalSecret peuvent recuperer **n'importe quel** secret accessible par l'IAM du ClusterSecretStore.
- Si le ClusterSecretStore est compromis ou mal configure, l'impact est cluster-wide.
- Granularite IAM difficile a maintenir (un seul SA, beaucoup d'usages).

### Partie 2 : Mitigations multi-tenancy

ESO fournit deux mecanismes pour restreindre la portee d'un ClusterSecretStore :

```yaml
# Sur le ClusterSecretStore : limiter aux namespaces qui matchent un label
spec:
  conditions:
    - namespaceSelector:
        matchLabels:
          team: frontend
    - namespaces:
        - team-a
        - team-b
```

**Pattern recommande pour grosses orgs** :
- Un ClusterSecretStore par "tenant" (equipe), avec son propre GSA et `conditions.namespaceSelector`
- Naming convention sur les secrets GCP (`team-a/<secret>`, `team-b/<secret>`)
- Policy OPA/Kyverno qui refuse les ExternalSecret hors du naming pattern de l'equipe

**Question** : Dans quel contexte recommanderiez-vous un `ClusterSecretStore` plutot que des `SecretStore` par namespace ? Et inversement ?

### Partie 3 : Quand ESO + GCP Secret Manager ne suffit pas -- bridge vers Vault

ESO + Secret Manager (GCP/AWS/Azure) gere les **secrets statiques** : la valeur change quand quelqu'un la rotate explicitement.

Vault apporte une feature qu'aucun cloud secret manager ne fait nativement : les **secrets dynamiques**.

| Cas d'usage | ESO + GCP Secret Manager | Vault |
|-------------|--------------------------|-------|
| Mot de passe DB partage entre tous les pods | Oui | Oui |
| Mot de passe DB **different par pod**, valable 1h, auto-revoque | Non | **Oui (database engine)** |
| Credentials AWS short-lived pour une app GCP | Non (sans glue code) | **Oui (AWS engine)** |
| Certificat TLS court generee a la demande | Cert-manager avec issuer GCP | **Oui (PKI engine)** |
| SSH host CA pour acces administrateur | Non | **Oui (SSH engine)** |

**Modele mental pour quelqu'un qui connait GCP** :

| GCP | Vault |
|-----|-------|
| Secret Manager API (geree) | Vault server (3-5 pods que **vous** operez) |
| Cloud KMS | Vault Transit, ou le KMS qui scelle Vault (auto-unseal) |
| Workload Identity (KSA -> GSA) | Kubernetes auth method (JWT du SA -> token Vault) |
| IAM binding | Vault policy |
| `gcloud secrets versions access latest` | `vault kv get secret/...` |
| **(aucun equivalent)** | **Dynamic secrets** |
| **(aucun equivalent -- Google gere)** | **Sealing/unsealing** (Vault demarre scelle, doit etre unseal a chaque restart) |

**Le cout cache de Vault** :
- Cluster HA Raft 3-5 noeuds que **vous** maintenez (vs API geree)
- Strategie de sealing/unsealing : si vous utilisez auto-unseal avec Cloud KMS, perdre la cle KMS = perdre Vault definitivement (les "recovery keys" ne suffisent pas)
- Upgrades, backups, audit log shipping
- Lease renewal storms : si 10k pods demarrent en meme temps, ils obtiennent tous des leases dans la meme seconde, et tous renouvelles dans la meme seconde 30 minutes plus tard. Raft traite serialise.

**Question architecture** : Vous demarrez un projet sur GKE. Quelles questions vous posez-vous pour decider entre `ESO + GCP Secret Manager` (option par defaut) et `Vault` ? Quel volume / quels cas d'usage justifient le passage a Vault ?

---

## Bonus 6 (lecture seule) : PushSecret -- le flux inverse

> Lecture seule sur le cluster partage (necessite la permission `secretmanager.versionAdder`).

ESO offre aussi `PushSecret` : prendre un **Secret K8s** et l'ecrire **vers** GCP Secret Manager. Le flux inverse d'un ExternalSecret.

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: push-cert-to-gcp
  namespace: cert-manager
spec:
  refreshInterval: 10s
  secretStoreRefs:
    - name: gcp-store
      kind: ClusterSecretStore
  selector:
    secret:
      name: my-tls-cert   # Secret K8s genere par cert-manager
  data:
    - match:
        secretKey: tls.crt
        remoteRef:
          remoteKey: prod-tls-cert
```

Cas d'usage reels :

1. **Bootstrap inverse** : cert-manager genere un certificat TLS dans K8s. PushSecret le copie vers GCP Secret Manager. Les autres clusters / les services hors-K8s le consomment depuis la.
2. **Distribution multi-cluster** : un seul cluster "leader" genere le secret, PushSecret le diffuse aux providers, les autres clusters le consomment via ExternalSecret.
3. **Migration entre providers** : pour passer de AWS Secrets Manager a GCP Secret Manager, PushSecret depuis K8s vers le nouveau provider, puis bascule du ExternalSecret.

**Question** : PushSecret peut-il **ecraser** une version existante dans GCP ? Quelles precautions / IAM pour eviter qu'un dev casse un secret prod via PushSecret ?

---

## Bonus 7 : Installer Vault soi-meme (30 min)

> ⚠️ **Disclaimer obligatoire avant de commencer** :
>
> Ce TP installe Vault en **mode `-dev`**, un mode "jouet" exclusivement pedagogique :
> - **Stockage en memoire** : tout est perdu au redemarrage du pod (pas de PV).
> - **Auto-unseal automatique** : vous ne verrez pas la ceremonie d'unsealing reelle (5 shards Shamir ou KMS) -- c'est justement le point delicat en prod.
> - **Root token connu** : `training-root-token` -- public, ecrit dans le manifest.
> - **TLS desactive** : HTTP en clair, pas de chiffrement reseau.
> - **Pas de HA** : un seul pod, pas de Raft.
>
> **Jamais en production**. Une vraie installation Vault production = 3-5 noeuds Raft + auto-unseal KMS + TLS + audit log + backups + procedure de rotation des unseal keys + 1 ingenieur dedie a son operation. L'objectif ici : comprendre l'API Vault et les concepts de base.

Chaque trainee deploie sa propre instance Vault dans le namespace `exercices`. Pas de conflit grace au prefixe `<NOM>`.

### Etape 1 : Deployer Vault dev mode

Creez le fichier `vault-dev.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-dev-<NOM>
  namespace: exercices
  labels:
    app: vault-dev-<NOM>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault-dev-<NOM>
  template:
    metadata:
      labels:
        app: vault-dev-<NOM>
    spec:
      containers:
        - name: vault
          image: hashicorp/vault:1.18
          args:
            - server
            - -dev
            - -dev-root-token-id=training-root-token
            - -dev-listen-address=0.0.0.0:8200
          ports:
            - containerPort: 8200
              name: api
          env:
            - name: VAULT_ADDR
              value: http://127.0.0.1:8200
            - name: VAULT_TOKEN
              value: training-root-token
          readinessProbe:
            httpGet:
              path: /v1/sys/health
              port: 8200
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: vault-dev-<NOM>
  namespace: exercices
spec:
  selector:
    app: vault-dev-<NOM>
  ports:
    - port: 8200
      targetPort: 8200
      name: api
```

Appliquez et attendez le pod Ready :

```bash
kubectl apply -f vault-dev.yaml
kubectl rollout status deploy/vault-dev-<NOM> -n exercices --timeout=120s
kubectl get pods -n exercices -l app=vault-dev-<NOM>
```

### Etape 2 : Premier contact avec la CLI Vault

Toutes les commandes `vault` s'executent **dans le pod** (la CLI est dans l'image) :

```bash
# Definir un alias pratique
alias v="kubectl exec -n exercices deploy/vault-dev-<NOM> -- vault"

# Status -- regardez Initialized=true, Sealed=false (dev mode auto-init + auto-unseal)
v status
```

Observez les champs renvoyes :
- `Sealed: false` -- en prod, le pod demarrerait avec `Sealed: true` et il faudrait fournir 3 unseal keys sur 5 avant qu'il accepte la moindre requete.
- `Storage Type: inmem` -- en memoire. Restart = perte de tout.
- `Cluster Name: vault-cluster-...` -- nom auto-genere.

### Etape 2.5 : Acceder a l'UI Vault dans le navigateur

Vault embarque une UI web sur le port 8200. On la rend accessible depuis votre laptop avec `kubectl port-forward` :

```bash
# Dans un terminal dedie (la commande reste bloquante) :
kubectl -n exercices port-forward deploy/vault-dev-<NOM> 8200:8200

# Forwarding from 127.0.0.1:8200 -> 8200
```

Ouvrez votre navigateur sur **http://localhost:8200/ui** :
- Method : `Token`
- Token : `training-root-token`

Vous arrivez sur le dashboard Vault. Explorez :
- **Secrets engines** : liste des mounts (`secret/` pour le KV, plus d'autres apres l'Etape 5)
- **Access** > **Auth methods** : `token`, et eventuellement `kubernetes`/`userpass` si vous les activez
- **Policies** : voyez la policy `root` (tout-puissante)
- **Tools** : encoder/decoder base64, wrap/unwrap de secrets

Gardez le port-forward ouvert dans un terminal -- les etapes suivantes utilisent indifferemment la CLI ou l'UI. Pour fermer : `Ctrl-C`.

> Tip : si le port 8200 est deja occupe sur votre machine, utilisez un autre port local : `kubectl ... port-forward ... 18200:8200` et ouvrez `http://localhost:18200/ui`.

### Etape 3 : Definir des secrets dans le KV engine (statique)

Le KV engine v2 est monte automatiquement en dev mode sur le chemin `secret/`. C'est l'equivalent fonctionnel de GCP Secret Manager.

#### 3.1 Secret simple a une cle

```bash
# Via CLI
v kv put secret/db-creds password=hello-from-vault

# Lire
v kv get secret/db-creds
```

Dans l'UI : **Secrets** > **secret/** > **Create secret** > path `db-creds`, key `password`, value `hello-from-vault`. Sauvegardez puis lisez. Notez le bandeau "Version 1".

#### 3.2 Secret structure (plusieurs cles dans un meme path)

Un secret n'est pas qu'une valeur -- c'est un dictionnaire. Tres pratique pour grouper logiquement :

```bash
# Un secret = plusieurs cles atomiques
v kv put secret/api/prod \
  db_user=api-prod \
  db_password=super-secret \
  db_host=postgres.prod.internal \
  api_key=sk-live-abc123 \
  feature_flag_premium=true

v kv get secret/api/prod
v kv get -field=db_password secret/api/prod   # extraire une seule cle
```

Dans l'UI : path `api/prod`, ajoutez les 5 cles avec **+ Add**. Notez que l'UI affiche les valeurs masquees par defaut (icone oeil pour reveler).

#### 3.3 Organiser les secrets en hierarchie (paths)

Vault accepte des chemins arbitrairement profonds, comme un filesystem. Utile pour separer par environnement / equipe / service :

```bash
v kv put secret/teams/backend/prod/db password=pg-prod-pass
v kv put secret/teams/backend/staging/db password=pg-staging-pass
v kv put secret/teams/frontend/prod/cdn token=cdn-prod-token

# Lister un sous-arbre
v kv list secret/teams/
v kv list secret/teams/backend/
```

Dans l'UI : **secret/** > naviguez dans les dossiers (`teams/` > `backend/` > `prod/` ...). C'est la base du modele d'autorisation Vault : les policies referencent des chemins exactement comme ca (ex : `path "secret/data/teams/backend/*" { capabilities = ["read"] }`).

#### 3.4 Metadata et description d'un secret

KV v2 permet d'attacher des metadonnees a un secret (pour audit / inventaire) :

```bash
v kv metadata put \
  -custom-metadata=owner=team-backend \
  -custom-metadata=created-by=hugo \
  -max-versions=10 \
  secret/api/prod

v kv metadata get secret/api/prod
```

Dans l'UI : ouvrez `api/prod` > onglet **Metadata** > **Edit metadata**. Vous y voyez aussi l'historique des versions (creation, suppression, destruction).

#### 3.5 Comparaison rapide avec GCP Secret Manager

| Operation | Vault | GCP Secret Manager |
|-----------|-------|---------------------|
| Ecrire un secret a 1 cle | `vault kv put secret/db password=x` | `gcloud secrets versions add db --data-file=-` (la valeur est une string opaque) |
| **Plusieurs cles dans un meme secret** | **Natif** (`vault kv put secret/api k1=v1 k2=v2`) | Non natif -- vous mettez du JSON dans la string et parsez cote app |
| Lire | `vault kv get secret/api` | `gcloud secrets versions access latest --secret=api` |
| Lister une hierarchie | `vault kv list secret/teams/` | Naming convention + `gcloud secrets list --filter` |
| Metadata custom | `vault kv metadata put -custom-metadata=...` | Labels GCP sur le secret |
| Versions | Auto-versionne (KV v2) | Auto-versionne |
| UI graphique | Oui (Vault UI built-in) | Oui (console GCP) |
| Stockage | Dans Vault (vous) | Dans Google (geree) |

### Etape 4 : Les versions (KV v2)

```bash
# Ecrivez une nouvelle valeur
v kv put secret/api db_password=v2-rotated api_key=99

# Lisez la derniere
v kv get secret/api

# Lisez la version 1
v kv get -version=1 secret/api

# Rollback : promouvoir la v1 comme actuelle
v kv rollback -version=1 secret/api
```

Note : c'est exactement la mecanique vue avec GCP Secret Manager + ESO `remoteRef.version: "1"`.

### Etape 5 : Le killer feature -- secret dynamique (PKI engine, ~10 min)

C'est ici que Vault depasse GCP Secret Manager. Vault devient une **autorite de certification** qui genere des certificats TLS courts a la demande -- chaque appel = un nouveau certificat unique.

```bash
# 1. Activer le secrets engine PKI
v secrets enable pki

# 2. Generer un certificat root (auto-signe, valide 1h)
v write pki/root/generate/internal common_name="training-ca-<NOM>" ttl=1h

# 3. Definir un role qui peut emettre des certs pour le domaine training.local
v write pki/roles/training-role \
  allowed_domains=training.local \
  allow_subdomains=true \
  max_ttl=5m

# 4. Generer un certificat -- valable 5 MINUTES
v write pki/issue/training-role \
  common_name=app-1.training.local \
  ttl=5m
```

Observez la sortie : vous obtenez un certificat X.509 complet (`certificate`, `private_key`, `serial_number`, `expiration`). Re-executez la derniere commande -- vous obtenez un **nouveau** certificat unique. Aucun stockage cote Vault : si l'app expose son cert, Vault sait quel `serial_number` est en circulation (`v list pki/certs`) mais le cle privee n'a jamais ete persistee.

**Ceci n'est pas faisable avec GCP Secret Manager**. Pour reproduire ce comportement chez GCP, il faudrait : une CA privee dans CA Service + une Cloud Function declenchee par l'app + IAM tres precise + caching cote app. Plusieurs jours de travail vs 4 commandes Vault.

### Etape 6 : Le moment de verite -- redemarrer Vault

```bash
# Tuez le pod
kubectl delete pod -n exercices -l app=vault-dev-<NOM>

# Attendez que le nouveau pod soit Ready
kubectl rollout status deploy/vault-dev-<NOM> -n exercices

# Listez vos secrets...
v kv list secret/
# No value found at secret/metadata/
```

**Tout est perdu.** En dev mode, le storage est en memoire. En prod, vous configurez un backend Raft (cluster Vault de 3-5 noeuds) ou Consul ou un cloud KV -- ET la procedure d'unsealing pour redemarrer chacun. C'est le sujet operationnel #1 de Vault.

### Nettoyage

```bash
kubectl delete deploy vault-dev-<NOM> -n exercices --ignore-not-found
kubectl delete svc vault-dev-<NOM> -n exercices --ignore-not-found
```

### Questions de synthese

1. Pour faire la meme chose qu'aux Etapes 3-4 (KV + versioning), `ESO + GCP Secret Manager` suffirait. Pourquoi quelqu'un choisirait Vault quand meme ?
2. L'Etape 5 (PKI dynamique) est le vrai differenciateur. Quels autres engines dynamiques de Vault ont un equivalent que vous auriez du construire vous-meme en GCP ? (Indice : `database/`, `aws/`, `ssh/`, `transit/`)
3. L'Etape 6 montre le talon d'Achille de Vault. Quels sont les composants d'une vraie installation prod que vous n'avez **pas** vus ici ? (Indice : auto-unseal, Raft, audit log, snapshots, K8s auth method, Vault Agent Injector)

### Pour aller (vraiment) plus loin -- ne pas faire en classe

Ce qu'un Vault de production ajoute par dessus ce que vous venez de voir :
- **Storage backend Raft** : 3-5 pods, replication consensus, snapshots S3/GCS quotidiens
- **Auto-unseal via Cloud KMS** : la cle KMS dechiffre la master key au demarrage, plus besoin des humains avec leurs unseal keys (mais perdre la cle KMS = perdre Vault definitivement)
- **K8s auth method** : un pod K8s s'authentifie aupres de Vault avec son JWT de ServiceAccount (equivalent de Workload Identity cote GCP)
- **Vault Agent Injector** : sidecar mute le pod a la creation, injecte les secrets dans `/vault/secrets/`, gere les leases et les renouvellements
- **External Secrets Operator** peut aussi utiliser Vault comme `SecretStore` -- c'est meme le cas d'usage le plus repandu d'ESO en grosse boite
