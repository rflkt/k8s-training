# Session 4 : Storage et base de donnees

> **Objectifs**
>
> - Comprendre les StatefulSets et leur difference avec les Deployments
> - Deployer PostgreSQL avec un volume persistant (PVC)
> - Utiliser un Service headless pour les StatefulSets
> - Tester la persistance des donnees apres suppression d'un pod
> - Connecter l'API a la base de donnees
> - Comprendre les compromis entre base de donnees self-hosted et managee

---

## Prerequis

- Sessions 1 et 2 terminees (API deployee avec son Service)
- Namespace `exercices` cree

---

## Etape 1 : Deployer PostgreSQL avec un StatefulSet

Ouvrez le fichier `starter/postgres-statefulset.yaml` et completez le `TODO` :

Ajoutez la section `volumeClaimTemplates` :

```yaml
volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
```

Deployez le StatefulSet :

```bash
kubectl apply -f starter/postgres-statefulset.yaml
```

Observez la creation :

```bash
# Voir le StatefulSet
kubectl get statefulset -n exercices

# Voir le pod (notez le nom avec un suffixe numerique : postgres-0)
kubectl get pods -n exercices -l app=postgres

# Voir le PVC cree automatiquement
kubectl get pvc -n exercices
```

---

## Etape 2 : Creer le Service headless

Ouvrez le fichier `starter/postgres-service.yaml` et completez le `TODO` :

Ajoutez `clusterIP: None` pour creer un Service headless.

Deployez :

```bash
kubectl apply -f starter/postgres-service.yaml
```

Un Service headless ne fournit pas de load-balancing. Il permet d'acceder directement aux pods par leur DNS : `postgres-0.postgres.exercices.svc.cluster.local`.

---

## Etape 3 : Se connecter a PostgreSQL

Utilisez `psql` via un pod temporaire :

```bash
kubectl run -n exercices psql --rm -it --image=postgres:17 -- \
  psql -h postgres.exercices.svc.cluster.local -U admin -d training
```

Le mot de passe est `training-password`.

Dans le shell psql :

```sql
-- Verifier la connexion
SELECT version();

-- Lister les tables
\dt
```

---

## Etape 4 : Initialiser le schema

Executez le script SQL fourni pour creer la table `items` :

```bash
# Copier le fichier SQL dans le pod postgres
kubectl cp starter/init-schema.sql exercices/postgres-0:/tmp/init-schema.sql

# Executer le script
kubectl exec -n exercices postgres-0 -- \
  psql -U admin -d training -f /tmp/init-schema.sql
```

Verifiez :

```bash
kubectl exec -n exercices postgres-0 -- \
  psql -U admin -d training -c "SELECT * FROM items;"
```

---

## Etape 5 : Tester la persistance

Supprimez le pod PostgreSQL et verifiez que les donnees sont conservees :

```bash
# Supprimer le pod
kubectl delete pod postgres-0 -n exercices

# Observer la recreation automatique
kubectl get pods -n exercices -l app=postgres -w

# Attendre que le pod soit Ready, puis verifier les donnees
kubectl exec -n exercices postgres-0 -- \
  psql -U admin -d training -c "SELECT * FROM items;"
```

Les donnees sont toujours la. Le PVC persiste meme quand le pod est supprime. C'est la difference fondamentale entre un StatefulSet avec PVC et un Deployment classique.

---

## Etape 6 : Connecter l'API a la base de donnees

Ouvrez le fichier `starter/api-deployment-db.yaml` et completez le `TODO` :

Ajoutez la variable d'environnement `DATABASE_URL` :

```yaml
- name: DATABASE_URL
  value: postgres://admin:training-password@postgres.exercices.svc.cluster.local:5432/training?sslmode=disable
```

Deployez la mise a jour :

```bash
kubectl apply -f starter/api-deployment-db.yaml
```

---

## Etape 7 : Tester les operations CRUD

Testez l'API connectee a la base de donnees :

```bash
kubectl port-forward svc/api 9090:80 -n exercices
```

Dans un autre terminal :

```bash
# Lister les items
curl http://localhost:9090/items

# Creer un item
curl -X POST http://localhost:9090/items \
  -H "Content-Type: application/json" \
  -d '{"name": "Nouvel item", "description": "Cree via API"}'

# Verifier
curl http://localhost:9090/items
```

---

## Discussion : Base de donnees self-hosted vs managee

Points a aborder en groupe :

- **Self-hosted (StatefulSet)** : controle total, cout reduit, mais responsabilite des backups, mises a jour, haute disponibilite
- **Managee (Cloud SQL, AlloyDB)** : backups automatiques, replicas, maintenance geree, mais cout plus eleve
- **En production chez RFLKT** : on utilise Cloud SQL pour PostgreSQL, avec connexion via Cloud SQL Auth Proxy
- **Quand utiliser un StatefulSet** : environnements de dev/test, cas ou le controle total est necessaire

---

## Bonus : Init container

Utilisez un init container pour initialiser automatiquement le schema au demarrage de PostgreSQL :

1. Creez un ConfigMap contenant le script SQL :
   ```bash
   kubectl create configmap postgres-init-schema \
     --from-file=init-schema.sql=starter/init-schema.sql \
     -n exercices
   ```

2. Modifiez le StatefulSet pour monter le ConfigMap dans `/docker-entrypoint-initdb.d/` :
   ```yaml
   volumeMounts:
     - name: postgres-data
       mountPath: /var/lib/postgresql/data
     - name: init-scripts
       mountPath: /docker-entrypoint-initdb.d
   volumes:
     - name: init-scripts
       configMap:
         name: postgres-init-schema
   ```

PostgreSQL execute automatiquement les scripts dans `/docker-entrypoint-initdb.d/` lors de la premiere initialisation de la base.

---

## Mini-defi

Mettez en place une strategie de backup pour PostgreSQL :

1. Creez un CronJob Kubernetes qui execute `pg_dump` toutes les heures
2. Stockez le dump dans un volume persistant separe
3. Testez la restauration a partir du dump

Exemple de CronJob :

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: exercices
spec:
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: backup
              image: postgres:17
              command:
                - /bin/sh
                - -c
                - pg_dump -h postgres -U admin training > /backups/backup-$(date +%Y%m%d-%H%M).sql
              env:
                - name: PGPASSWORD
                  value: training-password
          restartPolicy: OnFailure
```

Cet exercice vous prepare aux problematiques de gestion de donnees en production.
