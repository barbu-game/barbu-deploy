# Cluster Hetzner (kube-hetzner)

## Pré-requis
- Token API Hetzner (projet dédié).
- Clé SSH (`~/.ssh/id_ed25519[.pub]`).
- Deploy key (lecture) enregistrée sur `barbu-deploy`, partie privée dans `argocd_repo_ssh_key`.

## Apply
```bash
cp terraform.tfvars.example terraform.tfvars   # puis remplir les vraies valeurs
terraform init
terraform apply                                # crée les ressources FACTURÉES
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get nodes
```

## Détruire
```bash
terraform destroy
```
> La donnée Postgres vit sur un volume CSI : un `destroy` la supprime. Vérifier qu'un
> backup S3 récent existe (Plan 5) avant tout destroy.
