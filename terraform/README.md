# Cluster Hetzner (kube-hetzner)

## Pré-requis
- Token API Hetzner (projet dédié).
- Clé SSH (`~/.ssh/id_ed25519[.pub]`).
- Deploy key (lecture) enregistrée sur `barbu-deploy`, partie privée dans `argocd_repo_ssh_key`.

## Apply
```bash
cp terraform.tfvars.example terraform.tfvars   # puis remplir les vraies valeurs
terraform init                                 # PAS -upgrade (cf. « Patch ARM » ci-dessous)
# macOS : le module appelle GNU `timeout` dans ses provisioners → mettre coreutils devant le PATH
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
terraform apply                                # crée / modifie les ressources FACTURÉES
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get nodes
```
> **Avant tout `apply`**, vérifier que le patch ARM (ci-dessous) est en place, sinon le plan
> échoue en `no image found` :
> ```bash
> grep -A2 'microos_arm_snapshot' .terraform/modules/kube-hetzner/main.tf | grep with_architecture
> # doit afficher : with_architecture = "x86"   (et NON "arm")
> ```

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

### Patch ARM (capacité Ampere indisponible) — ⚠️ piège récurrent

Au montage initial, la capacité ARM Hetzner était épuisée (`resource_unavailable`
sur cax11/cax21 × fsn1/nbg1/hel1), donc **aucun snapshot ARM n'a été construit** — le projet
n'a qu'un snapshot **x86** (`microos-snapshot=yes`, arch `x86`).

Le module (v2.18.0) déclare le data source ARM en bloc `data` **sans `count`**, donc Terraform
l'**évalue à chaque plan/apply** même si le cluster est 100 % x86 (son id n'est lu que pour un
`server_type` commençant par `cax`, qu'on n'a pas). Sans snapshot ARM, cette évaluation échoue en
`no image found` et **bloque tout plan/apply**. D'où le patch : forcer le data source ARM sur `x86`.

**Le patch** (`.terraform/modules/kube-hetzner/main.tf`, data source `microos_arm_snapshot`) :
```hcl
data "hcloud_image" "microos_arm_snapshot" {
  with_selector     = "microos-snapshot=yes"
  with_architecture = "x86"    # ← patché ; l'original est "arm"
  most_recent       = true
}
```

**Ce qui l'écrase** : il vit dans le cache module `.terraform/modules/`, donc il saute à tout
**re-téléchargement du module** — c.-à-d. `terraform init -upgrade`, **ou** un `terraform init`
sur un **checkout frais** (pas de `.terraform/`). Un `terraform init` ordinaire sur un `.terraform`
déjà présent **ne le touche pas**. → **Ne pas lancer `init -upgrade`** ; après un checkout frais ou
un upgrade volontaire, **ré-appliquer le patch** (une ligne : `with_architecture` `arm`→`x86`) avant
tout apply.

**Les variables `microos_{x86,arm}_snapshot_id` n'aident pas** : en 2.18.0 elles sont déclarées mais
non câblées (le code référence directement `data.hcloud_image.microos_arm_snapshot.id`), donc les
fournir n'évite pas l'évaluation du data source.

**Décision (2026-07-15) : on garde le patch.** Bâtir un snapshot ARM juste pour satisfaire un data
source inutilisé ajoute plus de surface que le one-liner n'en retire. **Le construire seulement si on
ajoute un jour un nodepool ARM** (`cax…`) — là il faut un vrai snapshot arm de toute façon :
`packer build -only='hcloud.microos-arm-snapshot' …` puis retirer le patch (revenir à `arm`).

## Control-plane HA (3 membres etcd + LB)

`control_plane_nodepools` = **3 nodepools** (`control-plane`/nbg1, `control-plane-fsn`/fsn1,
`control-plane-hel`/hel1, count 1 chacun) → **quorum etcd 3, tolère 1 panne CP**. `use_control_plane_lb
= true` place un **LB Hetzner** devant les 3 apiservers → l'endpoint API est le LB (le kubeconfig
pointe l'IP du LB), pas une IP de CP. Pourquoi 3 CP : le control-plane sous-dimensionné étranglait
l'apiserver, ce qui privait le control-plane Linkerd de sa capacité à servir les nouveaux proxies
(pods meshés qui wedgent au boot) — 3 CP répartissent la charge de watches.

> **Migration 1→3 sur cluster vivant (fait 2026-07-15)** : le plan doit être **non destructif** — il
> ne doit CRÉER que les 2 nouveaux CP + le LB, et **re-run** (replace de `null_resource`) la config du
> CP existant + l'agent du worker ; **aucun `hcloud_server`/volume existant détruit** (vérifier avant
> apply : `grep hcloud_server /tmp/plan.txt | grep -iE 'destroyed|replaced'` doit être vide).
>
> ⚠️ **Gotcha — la reconfig de l'agent laisse le WORKER cordonné.** Pendant l'apply, k3s reconfigure
> l'agent du worker et le laisse `unschedulable` (taint `node.kubernetes.io/unschedulable`) sans le
> dé-cordonner → **tous les pods app passent `Pending` → site down**. Fix immédiat :
> `kubectl uncordon k3s-worker-zez`. Le pod Traefik (volume RWO acme.json) met ensuite ~30-60 s à
> réattacher son volume avant de servir. **Prévoir une courte fenêtre de coupure** pour ce type de
> migration control-plane.

## Détruire
```bash
terraform destroy
```
> La donnée Postgres vit sur un volume CSI : un `destroy` la supprime. Vérifier qu'un
> backup S3 récent existe (Plan 5) avant tout destroy.
