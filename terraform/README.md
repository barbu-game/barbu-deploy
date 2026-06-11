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

## Snapshots MicroOS (pré-requis kube-hetzner)

Le module lit **inconditionnellement** un snapshot x86 ET un snapshot ARM
(`data.hcloud_image.microos_{x86,arm}_snapshot`), même si le cluster n'a aucun
nœud ARM. Construits via Packer :
```bash
cd .terraform/modules/kube-hetzner/packer-template
HCLOUD_TOKEN=… packer build -only='hcloud.microos-x86-snapshot' hcloud-microos-snapshots.pkr.hcl
```
> La gamme CX a été renommée (cx22→**cx23**) : le template Packer upstream cible
> `cx22`, à corriger en `cx23` pour le build x86.

### Patch ARM (capacité Ampere indisponible)
Au montage initial, la capacité ARM Hetzner était épuisée (`resource_unavailable`
sur cax11/cax21 × fsn1/nbg1/hel1). Le cluster étant **100 % x86**, le snapshot ARM
est inerte (son id n'est lu que pour un `server_type` commençant par `cax`). On a donc
patché `.terraform/modules/kube-hetzner/main.tf` pour pointer le data source ARM sur
l'architecture `x86`. **Ce patch vit dans `.terraform` et saute à chaque `terraform init`** :
le ré-appliquer, ou — mieux — construire un vrai snapshot ARM quand la capacité revient
(`packer build -only='hcloud.microos-arm-snapshot' …`) puis retirer le patch.

## Détruire
```bash
terraform destroy
```
> La donnée Postgres vit sur un volume CSI : un `destroy` la supprime. Vérifier qu'un
> backup S3 récent existe (Plan 5) avant tout destroy.
