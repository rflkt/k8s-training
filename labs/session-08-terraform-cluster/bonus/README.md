# Session 8 — Exercices Bonus

> Pour ceux qui ont termine le TP principal en avance. Chaque exercice est independant.

---

## Bonus 1 : Ajouter un second node pool (20 min)

Le pool principal utilise des `e2-small`. Creez un **second node pool** avec une machine type differente (plus puissante) pour les charges de travail plus exigeantes :

1. Dans votre `main.tf`, creez un nouveau module `node_pool` avec une machine type `e2-medium` :

```hcl
module "node_pool_medium" {
  source = "./modules/node_pool"

  pool_name      = "${var.student_name}-pool-medium"
  location       = var.zone
  cluster_id     = module.cluster.cluster_id
  machine_type   = "e2-medium"
  node_count     = 1
  min_node_count = 1
  max_node_count = 2
  spot           = true
}
```

2. Planifiez et verifiez que seul le nouveau node pool est cree (le pool existant ne change pas) :

```bash
terraform plan
```

3. Appliquez :

```bash
terraform apply
```

4. Verifiez que vous avez deux node pools :

```bash
gcloud container node-pools list --cluster=<VOTRE_PRENOM>-cluster --zone=europe-west9-a
```

5. Listez les nodes et verifiez les machine types :

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,INSTANCE_TYPE:.metadata.labels.node\.kubernetes\.io/instance-type
```

6. (Optionnel) Ajoutez un **taint** a ce nouveau pool pour que seuls les pods tolerants (charges lourdes) y soient schedules :

```hcl
module "node_pool_medium" {
  # ... autres params ...

  taint_key    = "workload"
  taint_value  = "heavy"
  taint_effect = "NO_SCHEDULE"
}
```

Appliquez et verifiez :

```bash
kubectl describe nodes -l node.kubernetes.io/instance-type=e2-medium | grep -A 2 "Taints:"
```

**Question** : Pourquoi serait-il utile d'avoir des node pools avec des machine types differentes ? (Ex: calcul intensif, memoire, GPU)

---

## Bonus 2 : Activer le monitoring du cluster (15 min)

Activez les **metriques d'observabilite** du cluster GKE pour le monitoring :

1. Modifiez le module `cluster` pour activer le monitoring. Dans `modules/cluster/main.tf`, ajoutez :

```hcl
logging_config {
  enable_components = ["SYSTEM_COMPONENTS"]
}

monitoring_config {
  enable_components = ["SYSTEM_COMPONENTS"]
  managed_prometheus {
    enabled = true
  }
}
```

2. (Alternativement) Via la ligne de commande gcloud :

```bash
gcloud container clusters update <VOTRE_PRENOM>-cluster \
  --zone=europe-west9-a \
  --enable-cloud-logging \
  --enable-cloud-monitoring \
  --logging=SYSTEM_COMPONENTS \
  --monitoring=SYSTEM_COMPONENTS
```

3. Verifiez dans la console GCP ou via gcloud :

```bash
gcloud container clusters describe <VOTRE_PRENOM>-cluster \
  --zone=europe-west9-a \
  --format='value(loggingConfig,monitoringConfig)'
```

4. Attendez 2-3 minutes que les metriques s'accumulent, puis explorez les dashboards GCP :

```bash
# Ouvrir le dashboard Kubernetes Engine dans la console
# https://console.cloud.google.com/kubernetes/workloads?project=cloud-447406
```

**Question** : Quelles metriques GCP Monitoring vous semblent les plus importantes pour alerter en production ? (CPU cluster, memoire, pods en erreur, etc.)

---

## Bonus 3 : Visualiser le graphe Terraform (15 min)

Utilisez `terraform graph` pour visualiser les dependances entre ressources :

1. Generez le graphe au format DOT :

```bash
terraform graph > graph.dot
```

2. Installez Graphviz pour convertir le DOT en image :

```bash
# macOS
brew install graphviz

# Linux (Debian/Ubuntu)
sudo apt-get install graphviz
```

3. Convertissez en PNG :

```bash
dot -Tpng graph.dot -o graph.png
```

4. Ouvrez l'image :

```bash
# macOS
open graph.png

# Linux
xdg-open graph.png
```

Vous voyez une representation visuelle des dependances :
- `module.network` est cree en premier
- `module.cluster` depend de `module.network`
- `module.node_pool` depend de `module.cluster`

5. (Optionnel) Generez un graphe planifie (plus detail) :

```bash
terraform graph -plan tfplan > graph-plan.dot
dot -Tpng graph-plan.dot -o graph-plan.png
```

**Question** : Comment cette visualisation aide-t-elle a comprendre l'ordre de creation des ressources ? Pourquoi certaines ressources peuvent-elles etre creees en parallele ?

---

## Bonus 4 : Destruction et recreation du cluster (20 min)

Testez un **scenario complet** : destruction controllée et recreation :

1. Verifiez l'etat actuel :

```bash
kubectl get nodes
terraform state list | head -10
```

2. Plannifiez la destruction :

```bash
terraform plan -destroy
```

Lisez le plan. Vous devriez voir :
- Destruction du node pool
- Destruction du cluster
- Destruction du network

3. Detruisez (attention : cela supprime tout !) :

```bash
# D'abord, supprimez les ressources K8s (facultatif mais clean)
kubectl delete namespace exercices --ignore-not-found

# Puis Terraform
terraform destroy
```

Tapez `yes`. Attendez ~5 minutes.

4. Verifiez la destruction dans GCP :

```bash
gcloud container clusters list --zone=europe-west9-a
gcloud compute networks list --filter="name:*<VOTRE_PRENOM>*"
```

Tout doit être vide.

5. Recreez from scratch :

```bash
terraform apply
```

Attendez ~10-12 minutes (le control plane GKE represente ~10 min a lui seul).

6. Verifiez que le nouveau cluster fonctionne :

```bash
kubectl cluster-info
kubectl get nodes
```

**Question** : Combien de temps a pris la destruction ? Et la recreation ? Pourquoi le cluster est-il la ressource la plus longue a creer/detruire ?
