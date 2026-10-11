# Session 12 (module complémentaire) : Vault, identifiants générés et rotation

> **Module optionnel de 2 h**, en plus des 22 h du parcours. À faire après les sessions 5 et 6.
>
> **Objectifs**
> - Comprendre ce que Vault ajoute à un gestionnaire de secrets : une identité par app, une politique par chemin, des identifiants qu'il génère et fait tourner lui-même
> - Authentifier un pod auprès de Vault avec son ServiceAccount (Kubernetes auth)
> - Monter des secrets Vault dans un pod avec le CSI driver, comme en session 5
> - Générer des identifiants PostgreSQL à la demande (dynamic role) et observer leur révocation
> - Faire tourner le mot de passe d'un login existant (static role) et **voir ce que ça casse**
> - Connaître les pièges qui font tomber une prod pendant une migration vers Vault

En octobre 2026, nous avons migré notre propre production de GCP Secret Manager vers Vault, et mis en place la rotation automatique des mots de passe de base de données sur une plateforme que nous opérons pour un client. Ce module en est tiré : chaque piège de l'étape 8 nous est arrivé, et la fenêtre d'erreur de l'étape 7 a été mesurée sur un vrai cluster avant d'être écrite ici.

Tout tourne en local sur kind. Pas de compte cloud, pas de coût.

---

## Les notions (40 min)

### Ce que Secret Manager ne fait pas

En session 6, l'app lit des secrets **que quelqu'un a créés** dans GCP Secret Manager. Trois questions restent sans bonne réponse :

1. **Qui a le droit de lire quoi ?** Avec un compte de service partagé par toutes les apps, chaque app peut lire les secrets de toutes les autres.
2. **Que se passe-t-il quand un mot de passe fuit ?** Il reste valide jusqu'à ce qu'un humain pense à le changer, partout où il est copié.
3. **Qui connaît le mot de passe de la base ?** Celui qui l'a créé, et tous ceux qui ont eu accès au secret depuis.

Vault répond aux trois avec une chaîne simple :

```
ServiceAccount du pod ──► méthode d'auth ──► politique ──► moteur de secrets ──► bail
     (identité)          (kubernetes)       (chemins)     (kv, database)      (durée de vie)
```

- **Identité.** Le pod présente le token de son ServiceAccount. Vault le fait valider par l'API Kubernetes (TokenReview). Pas de mot de passe pour se connecter à Vault : l'identité, c'est le ServiceAccount.
- **Politique.** Un rôle Vault relie un ServiceAccount précis à une politique. La politique liste les chemins lisibles. Une app, une politique, un rôle.
- **Moteur de secrets.** `kv` stocke des valeurs que vous écrivez. `database` **fabrique** des identifiants PostgreSQL et les fait tourner.
- **Bail (lease).** Un identifiant généré a une durée de vie. À expiration, Vault le révoque lui-même.

### Statique ou dynamique : le choix qui compte

| | Dynamic role | Static role |
|---|---|---|
| Ce que Vault fait | Crée un **nouvel utilisateur** PostgreSQL à chaque lecture, le supprime à la fin du bail | Garde **un login existant** et change son mot de passe à intervalle régulier |
| Une fuite vaut | Jusqu'à la fin du bail (minutes) | Jusqu'à la prochaine rotation |
| Idéal pour | Un humain qui se connecte 10 min, un job batch | Une app qui garde un pool de connexions ouvert |
| Le piège | Le bail expire sous les connexions ouvertes de l'app | La fenêtre entre la rotation et le moment où l'app lit le nouveau mot de passe |

Nous utilisons des **static roles pour les apps** et des **dynamic roles pour les humains**. L'étape 7 montre pourquoi le static role a son propre piège.

### La « rotation root »

Pour créer des utilisateurs et changer des mots de passe, Vault se connecte à PostgreSQL avec un compte à lui (`vault_admin`). Juste après la configuration, on demande à Vault de **changer le mot de passe de ce compte**. Plus personne ne le connaît, Vault compris côté humain : il n'existe que dans Vault.

---

## Prérequis

- Un cluster kind qui tourne (`kind create cluster --config setup/kind-config.yaml --name training`)
- `kubectl`, `helm`, `docker`. Pas besoin de la CLI `vault` : on l'utilise depuis le pod Vault.
- Sessions 5 et 6 faites (CSI driver, SecretProviderClass)

Toutes les commandes se lancent depuis `labs/session-12-vault/`.

---

## Étape 0 : l'image de l'API et le namespace (5 min)

L'API de la formation sait maintenant lire ses identifiants de base de données **dans deux fichiers, à chaque nouvelle connexion** (variables `DB_USER_FILE` et `DB_PASSWORD_FILE`). C'est ce qui lui permet de suivre une rotation. Une app qui lit son mot de passe une fois au démarrage, dans une variable d'environnement, casse à la première rotation.

```bash
docker build -t api:vault --build-arg APP_VERSION=vault ../../app/api/
kind load docker-image api:vault --name training
kubectl create namespace exercices --dry-run=client -o yaml | kubectl apply -f -
```

---

## Étape 1 : installer le CSI driver et Vault (10 min)

Le CSI driver, avec la **rotation activée** : toutes les 30 s, il relit les secrets et réécrit les fichiers montés.

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm install csi secrets-store-csi-driver/secrets-store-csi-driver \
  --version 1.6.1 -n kube-system \
  --set enableSecretRotation=true \
  --set rotationPollInterval=30s
```

Vault, en mode dev, avec son provider CSI. Lisez `starter/vault-values.yaml` avant de lancer :

```bash
helm install vault hashicorp/vault --version 0.34.0 \
  -n vault --create-namespace -f starter/vault-values.yaml --wait

kubectl -n vault get pods
# vault-0 et un vault-csi-provider-xxxxx par nœud, tous Running
```

Pour la suite, un alias pratique (le token root du mode dev vaut `root`) :

```bash
alias v='kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN=root vault'
v status
```

---

## Étape 2 : PostgreSQL et ses trois rôles (5 min)

Lisez `starter/postgres.yaml`. Le script d'init crée trois rôles :

| Rôle | Login | Rôle dans le lab |
|---|---|---|
| `app_owner` | non | Possède les tables. Personne ne se connecte avec. |
| `api_app` | oui | Le login de l'API. Vault fera tourner son mot de passe. Il agit en tant que `app_owner`. |
| `vault_admin` | oui | Le compte de Vault (la rotation root). |

Pourquoi `app_owner` ? Si l'API créait ses tables en tant que `api_app`, ou pire en tant qu'un utilisateur dynamique, ces tables appartiendraient à un login qui peut disparaître. Révoquer l'utilisateur échouerait, et les tables seraient orphelines. Tout ce que l'app crée doit appartenir à un rôle qui ne se connecte jamais.

```bash
kubectl apply -f starter/postgres.yaml
kubectl -n exercices rollout status deploy/postgres
```

---

## Étape 3 : un premier secret dans KV (5 min)

```bash
v secrets enable -path=kv kv-v2
v kv put kv/exercices/api API_KEY="ma-cle-api-$(date +%s)"
v kv get kv/exercices/api
```

> **Piège KV v2.** La CLI dit `kv/exercices/api`, mais le **chemin d'API** (celui des politiques et de la SecretProviderClass) est `kv/data/exercices/api`. Oublier `data/` donne un « permission denied » qui n'a rien à voir avec les droits.

---

## Étape 4 : l'identité du pod (15 min)

### 4.1 Activer Kubernetes auth

Vault tourne dans le cluster : il sait joindre l'API Kubernetes et valider les tokens avec son propre ServiceAccount.

```bash
v auth enable kubernetes
v write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc"
```

### 4.2 La politique de l'API

Complétez `starter/policy-api.hcl` (deux TODO), puis :

```bash
v policy write api - < starter/policy-api.hcl
v policy read api
```

### 4.3 Le rôle : ce ServiceAccount, cette politique

```bash
v write auth/kubernetes/role/api \
  bound_service_account_names=api \
  bound_service_account_namespaces=exercices \
  audience=vault \
  token_policies=api \
  token_ttl=20m
```

Lisez-le à voix haute : « un pod qui tourne sous le ServiceAccount `api` du namespace `exercices` reçoit un token Vault de 20 min avec la politique `api` ». Rien d'autre ne passe.

---

## Étape 5 : le moteur database (20 min)

### 5.1 Brancher Vault sur PostgreSQL

```bash
v secrets enable database

v write database/config/app \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres.exercices.svc.cluster.local:5432/app?sslmode=disable" \
  allowed_roles="api,api-dynamic" \
  username=vault_admin \
  password=bootstrap-password-rotated-by-vault
```

### 5.2 La rotation root

```bash
v write -force database/rotate-root/app
```

Vérifiez que le mot de passe d'origine ne marche plus :

```bash
kubectl -n exercices exec deploy/postgres -- \
  env PGPASSWORD=bootstrap-password-rotated-by-vault \
  psql -h postgres.exercices.svc.cluster.local -U vault_admin -d app -c "SELECT 1"
# FATAL: password authentication failed for user "vault_admin"
```

> Pourquoi pas `-h localhost` ? Dans le conteneur, l'image officielle de PostgreSQL fait confiance (`trust`) aux connexions locales : n'importe quel mot de passe passe, et le test ne prouve rien. En passant par le Service, on est authentifié comme l'API.

Le mot de passe du compte qui peut créer des utilisateurs dans votre base n'est plus connu de personne.

### 5.3 Un identifiant dynamique

```bash
v write database/roles/api-dynamic db_name=app default_ttl=2m max_ttl=10m \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE app_owner; ALTER ROLE \"{{name}}\" SET role = 'app_owner';" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";"

v read database/creds/api-dynamic
```

Notez le `username` (`v-token-api-dyna-...`) et le `lease_duration` (2 min). Dans PostgreSQL :

```bash
kubectl -n exercices exec deploy/postgres -- psql -U postgres -d app \
  -c "SELECT rolname, rolvaliduntil FROM pg_roles WHERE rolname LIKE 'v-%';"
```

Attendez 2 minutes et relancez la requête : **l'utilisateur a disparu**. Personne n'a rien fait. C'est le bail.

> Le `SET role = 'app_owner'` de la création fait que tout ce que cet utilisateur crée appartient à `app_owner`. C'est ce qui permet au `DROP ROLE` de la révocation de réussir.

### 5.4 Un static role : le login de l'API

```bash
v write database/static-roles/api db_name=app username=api_app rotation_period=120s
v read database/static-creds/api
```

Deux choses à remarquer :

- **Le mot de passe a déjà changé.** Vault fait une première rotation **au moment où il adopte le login**, pas au premier tick. Le mot de passe initial du script d'init ne sert plus. En production, c'est la mise en ligne elle-même qui déclenche la première rotation, pas « cette nuit à 3 h ».
- `rotation_period=120s` est **réglé pour le lab**, pour voir une rotation en direct. En production : une rotation planifiée à une heure creuse (`rotation_schedule="0 3 * * *"`).

> Retard ? `./solution/vault-setup.sh` refait les étapes 3 à 5.

---

## Étape 6 : déployer l'API (15 min)

Complétez `starter/secret-provider-class.yaml` (3 TODO) et `starter/api-deployment-vault.yaml` (3 TODO). C'est le même objet qu'en session 5 : seul le `provider` change. Le pod ne sait pas d'où viennent ses fichiers.

```bash
kubectl apply -f starter/secret-provider-class.yaml -f starter/api-deployment-vault.yaml
kubectl -n exercices rollout status deploy/api
```

Un pod de test pour interroger l'API :

```bash
kubectl -n exercices run curl --image=curlimages/curl:8.10.1 --restart=Never --command -- sleep 3600
alias c='kubectl -n exercices exec curl -- curl -s'

c http://api/db-identity
# {"current_user":"app_owner","session_user":"api_app"}
c http://api/secret-test
# {"path":"/mnt/secrets-store/api-key","secret_exists":"true"}
c -X POST -H 'Content-Type: application/json' -d '{"name":"premier"}' http://api/items
```

`session_user` est le login dont Vault fait tourner le mot de passe, et `current_user` le rôle qui possède les tables.

### 6.1 Prouver le moindre privilège

Le même montage, depuis un pod qui tourne sous le ServiceAccount `default` :

```bash
kubectl -n exercices run intrus --image=api:vault --overrides='{"spec":{"serviceAccountName":"default","containers":[{"name":"intrus","image":"api:vault","volumeMounts":[{"name":"s","mountPath":"/mnt/secrets-store"}]}],"volumes":[{"name":"s","csi":{"driver":"secrets-store.csi.k8s.io","readOnly":true,"volumeAttributes":{"secretProviderClass":"api-vault"}}}]}}'

kubectl -n exercices describe pod intrus | grep -A2 FailedMount
# Code: 403 ... service account name not authorized

kubectl -n exercices delete pod intrus
```

Le pod reste bloqué en `ContainerCreating`. Il ne démarre jamais sans ses secrets, et il ne les obtiendra pas.

---

## Étape 7 : observer une rotation (15 min)

Toutes les 13 s pendant 4 min, on affiche le mot de passe côté Vault, celui du fichier monté dans le pod, et le code HTTP d'une écriture :

```bash
for i in $(seq 1 18); do
  vp=$(v read -field=password database/static-creds/api | cut -c1-6)
  fp=$(kubectl -n exercices exec deploy/api -- cat /mnt/secrets-store/db-password | cut -c1-6)
  code=$(kubectl -n exercices exec curl -- curl -s -o /dev/null -w '%{http_code}' \
    -X POST -H 'Content-Type: application/json' -d "{\"name\":\"t$i\"}" http://api/items)
  echo "$(date +%T) vault=$vp fichier=$fp POST=$code"
  sleep 13
done
```

Ce que nous avons obtenu en préparant ce module :

```
19:04:31 vault=wGFZDj fichier=wGFZDj POST=201
19:04:44 vault=AdQeYY fichier=wGFZDj POST=201   <- Vault a tourné, le fichier pas encore
19:04:57 vault=AdQeYY fichier=wGFZDj POST=500   <- une nouvelle connexion avec l'ancien mot de passe
19:05:11 vault=AdQeYY fichier=AdQeYY POST=201   <- le CSI driver a réécrit le fichier
```

**Lisez bien ces quatre lignes, c'est le cœur du module.**

- Vault change le mot de passe dans PostgreSQL **immédiatement**.
- Le CSI driver ne relit Vault que toutes les 30 s (`rotationPollInterval`). Entre les deux, le fichier contient un mot de passe qui ne marche plus.
- Les connexions **déjà ouvertes** continuent de fonctionner : PostgreSQL ne coupe pas une session quand son mot de passe change. D'où le 201 de 19:04:44.
- Une **nouvelle** connexion pendant la fenêtre échoue. L'API recycle ses connexions toutes les minutes (`SetConnMaxLifetime`), donc elle finit par en ouvrir une : 500.
- Dès que le fichier est réécrit, l'API repart **sans redémarrer**, parce qu'elle relit le fichier à chaque connexion.

La fenêtre dure au plus `rotationPollInterval`. Ce qui la réduit, par ordre d'efficacité :

1. **L'app relit le fichier à chaque connexion** (fait ici). Sans ça, il faut redémarrer le pod à chaque rotation : c'est une coupure, pas une fenêtre.
2. **Raccourcir le poll** (15 s au lieu de 2 min chez un de nos clients : la coupure est passée de 2 min 45 s à environ 35 s). Ça ne coûte rien tant que les apps ne montent que du KV et des static roles : un poll ne crée aucun identifiant.
3. **Ne pas brancher la liveness probe sur la base.** Sinon, pendant la fenêtre, Kubernetes tue un pod qui allait se rétablir tout seul, et le redémarrage s'ajoute à la coupure.
4. **Planifier la rotation à une heure creuse** (`rotation_schedule`), pour que la fenêtre tombe quand personne n'écrit.

> **Mini-défi.** Réduisez la fenêtre, relancez la boucle, et comparez :
>
> ```bash
> helm upgrade csi secrets-store-csi-driver/secrets-store-csi-driver \
>   --version 1.6.1 -n kube-system --reuse-values --set rotationPollInterval=10s
> ```
>
> Puis réfléchissez : pourquoi ne pas mettre 1 s ? (Indice : chaque cycle, c'est une lecture dans Vault par pod et par secret, sur tout le cluster.)

---

## Étape 8 : les pièges de production (10 min)

### 8.1 Ajouter une clé qui n'existe pas encore dans Vault

Vous ajoutez une entrée à la SecretProviderClass d'une app déjà sur Vault, mais vous n'avez pas encore écrit la valeur dans Vault. **Le montage échoue**, et le pod ne démarre pas :

```
MountVolume.SetUp failed ... {kv/data/exercices/api}: {key "NEW_KEY" does not exist at the secret path}
```

Avec un rolling update, le nouveau pod reste bloqué pendant que l'ancien continue de servir. Avec un Deployment en `Recreate` (un volume persistant, une seule réplique), l'ancien pod est déjà parti : **l'app est coupée**.

**Règle : la valeur dans Vault d'abord, la SecretProviderClass ensuite.**

### 8.2 Modifier une SecretProviderClass ne remonte pas les pods existants

Le CSI driver monte les fichiers à la création du pod. Changer la SecretProviderClass ne déclenche rien sur les pods déjà lancés : l'`apply` est vert, et la nouvelle variable n'est jamais là.

**Règle : après un changement de SecretProviderClass, `kubectl rollout restart`.** Ou, comme dans `api-deployment-vault.yaml`, une annotation de pod qu'on change en même temps pour forcer le roulement.

### 8.3 La première rotation, c'est la mise en ligne

Vu à l'étape 5.4 : Vault fait tourner le mot de passe d'un static role **dès qu'il l'adopte**. Si l'app lit encore son mot de passe dans un autre secret, elle casse **pendant la mise en ligne**. C'est plutôt une bonne nouvelle : c'est là que quelqu'un regarde.

### 8.4 PostgreSQL 16 : `CREATEROLE` ne suffit plus

Depuis PostgreSQL 16, un compte `CREATEROLE` ne peut modifier que les rôles sur lesquels il a l'option `ADMIN`. Sans `GRANT api_app TO vault_admin WITH ADMIN OPTION` (voir `postgres.yaml`), la création du static role échoue. Ça échoue à l'`apply`, pas à 3 h du matin, justement grâce à 8.3.

### 8.5 Des identifiants dynamiques derrière le CSI driver

Tentant : monter `database/creds/...` directement dans l'app. Mais le CSI driver ne renouvelle pas les baux : **il redemande un nouvel identifiant à chaque cycle**. Nous l'avons mesuré : un nouvel utilisateur PostgreSQL toutes les 30 à 60 s, et les anciens ne disparaissent qu'à l'expiration de leur bail. Avec un TTL long, ils s'accumulent. Avec un TTL court, l'utilisateur des connexions ouvertes expire sous l'app. Pour une app derrière le CSI driver : un static role.

### 8.6 Un seul fichier `~/.vault-token` pour plusieurs Vault

`vault login` écrit son token dans `~/.vault-token`. Si vous travaillez avec deux Vault (le vôtre et celui d'un client), le deuxième login écrase le premier, et la commande suivante répond 403 « invalid token » sans raison apparente. Utilisez `vault login -no-store` et un fichier de token par Vault.

---

## Ce qui change en production

Le mode dev est fait pour apprendre. En production, voici ce que nous faisons à la place :

| Lab | Production |
|---|---|
| Un pod, stockage en mémoire | 3 réplicas, stockage Raft intégré, réplication entre pods |
| Token root `root` | `vault operator init` lancé une fois par un workflow, le token root **révoqué** aussitôt, jamais stocké |
| Descellement : aucun (mode dev) | Auto-unseal par une clé Cloud KMS, avec **rotation automatique de la clé** (KMS garde les anciennes versions, Vault rechiffre au scellement suivant) |
| Clés de récupération : aucune | 5 parts, seuil de 3, rangées comme matériel de dernier recours. Les utiliser = un incident déclaré |
| Vault joignable dans le cluster | Aucune adresse publique : joignable seulement depuis le réseau privé de l'équipe |
| Configuration à la main | Terraform gère le mount KV, l'audit, Kubernetes auth, une politique et un rôle par app (bonus 1) |
| Humains : token root | Connexion avec Google Workspace (OIDC), domaine de l'entreprise uniquement, droits par personne |
| CI : rien | Aucune clé longue durée : GitHub Actions présente son token OIDC, Vault l'échange contre un token d'une heure (bonus 2) |
| `rotation_period=120s` | `rotation_schedule` à une heure creuse |

Et la migration elle-même s'est faite **app par app**, avec un retour arrière d'une ligne : chaque app avait un réglage `gcp` ou `vault`, et revenir à `gcp` remettait le montage Secret Manager, dont les secrets étaient laissés en place jusqu'à la fin.

---

## Nettoyage

```bash
kubectl delete namespace exercices
helm uninstall vault -n vault && kubectl delete namespace vault
helm uninstall csi -n kube-system
```

Bonus : [bonus/README.md](bonus/README.md) (Vault en Terraform, CI sans clé).
