# Session 4 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.
> Pensez a remplacer `<NOM>` par votre prenom dans tous les fichiers YAML et commandes.

---

## Bonus 1 : Init Container pour initialiser PostgreSQL (20 min)

Utilisez un init container pour attendre que PostgreSQL soit pret avant de demarrer l'API.

1. Creez le fichier `postgres-init-wait.yaml` :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-with-db-wait-<NOM>
  namespace: exercices
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-wait-<NOM>
  template:
    metadata:
      labels:
        app: api-wait-<NOM>
    spec:
      initContainers:
        - name: wait-for-postgres
          image: postgres:17
          env:
            - name: PGHOST
              value: postgres-<NOM>.exercices.svc.cluster.local
            - name: PGUSER
              value: admin
            - name: PGPASSWORD
              value: training-password
          command:
            - /bin/sh
            - -c
            - |
              echo "En attente de PostgreSQL..."
              until pg_isready -h $PGHOST -U $PGUSER; do
                echo "PostgreSQL n'est pas pret, nouvelle tentative dans 2s..."
                sleep 2
              done
              echo "PostgreSQL est pret !"
      containers:
        - name: api
          image: europe-west9-docker.pkg.dev/cloud-447406/training/api:v1
          ports:
            - containerPort: 8080
          env:
            - name: DATABASE_URL
              value: postgres://admin:training-password@postgres-<NOM>.exercices.svc.cluster.local:5432/training?sslmode=disable
            - name: ENVIRONMENT
              value: training
```

2. Appliquez le manifest :

```bash
kubectl apply -f postgres-init-wait.yaml
```

3. Observez le comportement du init container :

```bash
# Verifiez que le pod attend
kubectl get pods -n exercices -l app=api-wait-<NOM> -w

# Verifiez les logs du init container (en parallele)
kubectl logs -f deployment/api-with-db-wait-<NOM> -n exercices -c wait-for-postgres

# Une fois que le pod est Ready, verifiez que l'API est accessible
kubectl port-forward deployment/api-with-db-wait-<NOM> 9090:8080 -n exercices

# Dans un autre terminal
curl http://localhost:9090/health
```

4. Testez la robustesse : supprimez PostgreSQL et verifiez que l'API plante jusqu'a sa restoration :

```bash
# Supprimez le StatefulSet PostgreSQL (si vous le souhaitez)
# kubectl delete statefulset postgres-<NOM> -n exercices

# Le pod API va rester en attente jusqu'a ce que PostgreSQL soit a nouveau disponible
```

**Question** : Quels sont les avantages d'utiliser un init container plutot que de gerer la logique de reconnexion dans le code de l'application ?

---

## Bonus 2 : CronJob pour les backups PostgreSQL (20 min)

Configurez un CronJob qui sauvegarde PostgreSQL regulierement.

1. Creez d'abord un PVC pour stocker les backups :

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backups-pvc-<NOM>
  namespace: exercices
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

2. Creez le CronJob de backup :

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup-<NOM>
  namespace: exercices
spec:
  # Chaque heure, a la minute 0
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: default
          containers:
            - name: backup
              image: postgres:17
              env:
                - name: PGHOST
                  value: postgres-<NOM>.exercices.svc.cluster.local
                - name: PGUSER
                  value: admin
                - name: PGPASSWORD
                  value: training-password
                - name: PGDATABASE
                  value: training
              command:
                - /bin/sh
                - -c
                - |
                  BACKUP_FILE="/backups/backup-$(date +%Y%m%d-%H%M%S).sql"
                  echo "Demarrage du backup vers $BACKUP_FILE"
                  pg_dump -h $PGHOST -U $PGUSER > $BACKUP_FILE
                  echo "Backup termine: $(du -h $BACKUP_FILE | cut -f1)"
                  # Garder seulement les 5 derniers backups
                  ls -t /backups/backup-*.sql | tail -n +6 | xargs rm -f
              volumeMounts:
                - name: backups-storage
                  mountPath: /backups
          volumes:
            - name: backups-storage
              persistentVolumeClaim:
                claimName: backups-pvc-<NOM>
          restartPolicy: OnFailure
```

3. Appliquez les manifests :

```bash
kubectl apply -f backups-pvc.yaml
kubectl apply -f postgres-backup-cronjob.yaml
```

4. Verifiez les CronJobs :

```bash
# Lister les CronJobs
kubectl get cronjobs -n exercices

# Voir les Jobs crees par le CronJob
kubectl get jobs -n exercices | grep postgres-backup

# Voir les logs du dernier Job
JOB=$(kubectl get jobs -n exercices -l cronjob-name=postgres-backup-<NOM> --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs -f job/$JOB -n exercices
```

5. Verifiez les fichiers de backup :

```bash
# Listez les backups
kubectl run backup-explorer-<NOM> --image=busybox:1.35 --rm -it -n exercices -- \
  ls -lh /backups 2>/dev/null || echo "Le pod n'a pas pu acceder au PVC"

# Alternativement, attendez la prochaine execution et explorez via un pod temporaire
```

**Question** : Comment pourriez-vous automatiser la restauration d'un backup ? Quels elements faudrait-il verifier avant de restaurer ?

---

## Bonus 3 : EmptyDir pour partager des donnees entre conteneurs (15 min)

Utilisez un volume `emptyDir` pour partager un repertoire temporaire entre deux conteneurs d'un StatefulSet.

1. Creez un StatefulSet postgres avec un conteneur auxiliaire qui nettoie les fichiers temporaires :

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-with-cleanup-<NOM>
  namespace: exercices
spec:
  serviceName: postgres-with-cleanup-<NOM>
  replicas: 1
  selector:
    matchLabels:
      app: postgres-cleanup-<NOM>
  template:
    metadata:
      labels:
        app: postgres-cleanup-<NOM>
    spec:
      containers:
        - name: postgres
          image: postgres:17
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: admin
            - name: POSTGRES_PASSWORD
              value: training-password
            - name: POSTGRES_DB
              value: training
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
            - name: temp-storage
              mountPath: /tmp/postgres-work
        - name: temp-cleaner
          image: busybox:1.35
          command:
            - /bin/sh
            - -c
            - |
              echo "Nettoyeur de fichiers temporaires demarre"
              while true; do
                # Nettoyez les fichiers temporaires toutes les 5 minutes
                echo "$(date): nettoyage des fichiers temporaires"
                find /tmp/postgres-work -type f -mmin +5 -delete 2>/dev/null || true
                sleep 300
              done
          volumeMounts:
            - name: temp-storage
              mountPath: /tmp/postgres-work
      volumes:
        - name: temp-storage
          emptyDir: {}
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

2. Appliquez et verifiez :

```bash
kubectl apply -f postgres-with-cleanup.yaml

# Verifiez les deux conteneurs
kubectl get pods -n exercices -l app=postgres-cleanup-<NOM>

# Verifiez les logs du nettoyeur
kubectl logs -f pod/postgres-with-cleanup-<NOM>-0 -n exercices -c temp-cleaner
```

3. Testez le partage du volume :

```bash
# Creez un fichier dans le volume emptyDir via PostgreSQL
kubectl exec postgres-with-cleanup-<NOM>-0 -n exercices -c postgres -- \
  touch /tmp/postgres-work/test-file.txt

# Verifiez que le nettoyeur peut le voir
kubectl exec postgres-with-cleanup-<NOM>-0 -n exercices -c temp-cleaner -- \
  ls -la /tmp/postgres-work/
```

**Question** : Pourquoi un `emptyDir` est-il ideal pour les fichiers temporaires ? Que se passe-t-il si le pod est supprime ?

---

## Bonus 4 : Restauration depuis un backup (15 min)

Testez la restauration d'un backup PostgreSQL.

1. Creez un script de restauration :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: restore-script-<NOM>
  namespace: exercices
data:
  restore.sh: |
    #!/bin/bash
    set -e
    
    echo "Script de restauration PostgreSQL"
    BACKUP_FILE="${1:-}"
    
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
      echo "Erreur: Backup introuvable: $BACKUP_FILE"
      exit 1
    fi
    
    echo "Restauration depuis $BACKUP_FILE..."
    psql -h $PGHOST -U $PGUSER -d training < "$BACKUP_FILE"
    echo "Restauration complete"
```

2. Verifiez les backups existants :

```bash
# Listez les Jobs crees par le CronJob
kubectl get jobs -n exercices -l cronjob-name=postgres-backup-<NOM> -o jsonpath='{.items[*].metadata.name}'

# Trouvez un Job et consultez ses logs pour connaitre le chemin du backup
JOB=$(kubectl get jobs -n exercices -l cronjob-name=postgres-backup-<NOM> --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl logs job/$JOB -n exercices | grep "backup-"
```

3. Testez la restauration (optionnel, a faire avec prudence) :

```bash
# Creez une sauvegarde de secours avant de restaurer
kubectl exec -n exercices postgres-<NOM>-0 -- \
  pg_dump -U admin training > /tmp/sauvegarde-secu.sql

# Restaurez depuis le backup
BACKUP_PATH="/backups/backup-XXXXXXX.sql"  # Remplacez avec un vrai chemin
kubectl exec -n exercices postgres-<NOM>-0 -- \
  psql -U admin training < "$BACKUP_PATH"
```

**Question** : Qu'est-ce qui pourrait mal tourner lors d'une restauration en production ? Comment minimiseriez-vous les risques ?

