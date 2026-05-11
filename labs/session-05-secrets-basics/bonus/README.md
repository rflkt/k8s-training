# Session 5 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.
> Pensez a remplacer `<NOM>` par votre prenom dans tous les fichiers YAML et commandes.

---

## Bonus 1 : Multiple secrets dans un meme SecretProviderClass (20 min)

Montez plusieurs secrets GCP dans le meme volume CSI pour centraliser la gestion des secrets.

1. Les trois secrets sont **deja crees** dans GCP Secret Manager par le formateur (votre SA trainee n'a pas le droit `secretmanager.admin`). Vous pouvez les lister :

```bash
gcloud secrets list --project=cloud-447406 --filter='name~training'
# training-api-key, training-db-password, training-oauth-token
```

2. Creez un `SecretProviderClass` qui monte les trois secrets a des chemins differents :

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: multi-secrets-provider-<NOM>
  namespace: exercices
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/cloud-447406/secrets/training-api-key/versions/latest"
        path: "api-key"
      - resourceName: "projects/cloud-447406/secrets/training-db-password/versions/latest"
        path: "db-password"
      - resourceName: "projects/cloud-447406/secrets/training-oauth-token/versions/latest"
        path: "oauth-token"
```

3. Creez un Deployment qui monte le SecretProviderClass et utilise les secrets :

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-multi-secrets-<NOM>
  namespace: exercices
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-multi
  template:
    metadata:
      labels:
        app: api-multi
    spec:
      containers:
        - name: api
          image: europe-west9-docker.pkg.dev/cloud-447406/training/api:v1
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: secrets-store
              mountPath: /mnt/secrets-store
              readOnly: true
          env:
            - name: API_KEY_FILE
              value: /mnt/secrets-store/api-key
            - name: DB_PASSWORD_FILE
              value: /mnt/secrets-store/db-password
            - name: OAUTH_TOKEN_FILE
              value: /mnt/secrets-store/oauth-token
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: "multi-secrets-provider-<NOM>"
```

4. Appliquez et verifiez :

```bash
kubectl apply -f multi-secrets-provider.yaml
kubectl apply -f api-multi-secrets-deployment.yaml

# Attendez que le pod soit Ready
kubectl get pods -n exercices -l app=api-multi -w

# Verifiez que tous les secrets sont montes
kubectl exec -n exercices deploy/api-multi-secrets-<NOM> -- \
  ls -la /mnt/secrets-store/

# Verifiez le contenu de chaque secret
kubectl exec -n exercices deploy/api-multi-secrets-<NOM> -- \
  cat /mnt/secrets-store/api-key

kubectl exec -n exercices deploy/api-multi-secrets-<NOM> -- \
  cat /mnt/secrets-store/db-password

kubectl exec -n exercices deploy/api-multi-secrets-<NOM> -- \
  cat /mnt/secrets-store/oauth-token
```

5. Verifiez que les secrets ne sont pas visibles dans le manifeste :

```bash
kubectl get deployment api-multi-secrets-<NOM> -n exercices -o yaml | grep -i "secret"
# Devrait afficher uniquement les references au SecretProviderClass, pas les valeurs
```

**Question** : Quel est l'avantage de centraliser plusieurs secrets dans un meme SecretProviderClass ? Comment geriez-vous les rotations de secrets dans cette configuration ?

---

## Bonus 2 : Simulation de rotation de secrets (15 min)

Testez comment les secrets sont rafraichis quand vous les modifiez dans GCP.

1. Verifiez le secret initial :

```bash
kubectl exec -n exercices deploy/api-multi-secrets-<NOM> -- \
  cat /mnt/secrets-store/api-key
# Affiche : api-key-12345
```

2. Modifiez le secret dans GCP :

```bash
echo -n "api-key-99999-rotated" | gcloud secrets versions add training-api-key --data-file=-
```

3. Attendez que le pod se redéploie ou forcez la rotation en supprimant et recréant le pod :

```bash
# Le pod doit se redeployer pour recharger le secret
kubectl delete pod -l app=api-multi -n exercices

# Attendez que le nouveau pod soit cree
kubectl get pods -n exercices -l app=api-multi -w
```

4. Verifiez que le secret a ete rafraichi :

```bash
kubectl exec -n exercices deploy/api-multi-secrets-<NOM> -- \
  cat /mnt/secrets-store/api-key
# Affiche : api-key-99999-rotated
```

5. Observez la duree de la rotation :

```bash
# Verifiez les evenements du pod pour voir quand il a ete recree
kubectl describe pod -l app=api-multi -n exercices | grep -A 5 "Events:"
```

**Question** : Quel est le delai de propagation des secrets modifies ? Comment geriez-vous les rotations de secrets critiques sans downtime ?

---

## Bonus 3 : Sealed Secrets (concept et exploration) (15 min)

Decouvrez comment Sealed Secrets peut chiffrer vos secrets Kubernetes directement dans Git.

1. Installez Sealed Secrets (optionnel, sinon lisez la documentation) :

```bash
# Installation (si vous avez l'acces)
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.18.0/controller.yaml

# Verifiez que le controller est en cours d'execution
kubectl get pods -n kube-system | grep sealed-secrets

# Recuperez la cle publique pour chiffrer les secrets
kubeseal -f /dev/null -n exercices --print-sealed-key > sealing-key.pub
```

2. Creez un Secret classique :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-api-secret
  namespace: exercices
type: Opaque
stringData:
  api-key: "secret-key-12345"
  db-password: "db-pass-67890"
```

3. Chiffrez-le avec `kubeseal` (si installe) :

```bash
kubectl apply -f my-secret.yaml --dry-run=client -o yaml | \
  kubeseal -f - -n exercices > my-sealed-secret.yaml

# Le fichier chiffre peut maintenant etre commite dans Git sans risque
cat my-sealed-secret.yaml
```

4. Explorez la structure d'un Sealed Secret :

```bash
# Verifiez le contenu du fichier YAML
# Il contient des donnees chiffrees qui ne peuvent etre dechiffrees que
# par le controller Sealed Secrets du cluster
```

5. Lisez la documentation officielle pour comprendre les cas d'usage :

```bash
# Visitez : https://github.com/bitnami-labs/sealed-secrets
# Concepts clés :
# - Separation entre les cles publiques (partagees) et privees (secrets du cluster)
# - Chiffrement par namespace ou cluster
# - GitOps-friendly (les secrets chiffres peuvent etre commites)
```

**Question** : Quels sont les avantages de Sealed Secrets par rapport aux Secrets natifs Kubernetes ? Dans quel contexte (local, production, GitOps) recommenderiez-vous son utilisation ?

---

## Bonus 4 : Audit des acces aux Secrets (15 min)

Explorez les mecanismes de detection d'acces non autorise aux secrets.

1. Creez un Secret test :

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: audit-test-secret-<NOM>
  namespace: exercices
type: Opaque
data:
  password: cHJvdGVnZWQtcGFzc3dvcmQ=  # protected-password en base64
```

2. Appliquez le Secret :

```bash
kubectl apply -f audit-secret.yaml
```

3. Tentez d'acceder au Secret de differentes manieres et observez les logs :

```bash
# Acces direct au Secret (visible dans les logs d'audit)
kubectl get secret audit-test-secret-<NOM> -n exercices -o yaml

# Acces via les variables d'environnement d'un pod
kubectl set env deployment/api DB_SECRET=audit-test-secret-<NOM> -n exercices --from-secret

# Verifiez les logs d'audit du cluster (si disponibles)
# Sur GKE, l'audit logging passe par Cloud Logging :
# gcloud logging read 'protoPayload.methodName="io.k8s.core.v1.secrets.get"' --project=cloud-447406 --limit=10
```

4. Explorez les mecanismes de controle d'acces (RBAC) :

```bash
# Verifiez votre role RBAC
kubectl auth can-i get secrets -n exercices

# Verifiez qui peut acceder aux secrets
kubectl get rolebindings -n exercices -o yaml | grep -i secret

# Verifiez les permissions cluster-wide
kubectl get clusterrolebindings -o yaml | grep -i secret
```

5. Creez une politique RBAC restrictive :

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader-<NOM>
  namespace: exercices
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    # Ne permettre que les secrets specifiques
    resourceNames: ["audit-test-secret-<NOM>"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-reader-binding-<NOM>
  namespace: exercices
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: secret-reader-<NOM>
subjects:
  - kind: ServiceAccount
    name: default
    namespace: exercices
```

6. Appliquez et verifiez :

```bash
kubectl apply -f secret-reader-role.yaml

# Verifiez les permissions
kubectl get roles -n exercices
kubectl get rolebindings -n exercices
```

**Question** : Comment documenteriez-vous les regles d'acces aux secrets dans une equipe ? Quels elements faudrait-il auditer regulierement ?

