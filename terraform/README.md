# Hetzner cluster (kube-hetzner)

## Prerequisites
- Hetzner API token (dedicated project).
- SSH key (`~/.ssh/id_ed25519[.pub]`).
- Deploy key (read) registered on `barbu-deploy`, private half in `argocd_repo_ssh_key`.

## Apply
```bash
cp terraform.tfvars.example terraform.tfvars   # then fill in the real values
terraform init                                 # NOT -upgrade (see "ARM patch" below)
# macOS: the module calls GNU `timeout` in its provisioners → put coreutils ahead on the PATH
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
terraform apply                                # creates / modifies BILLED resources
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get nodes
```
> **Before any `apply`**, check that the ARM patch (below) is in place, otherwise the plan
> fails with `no image found`:
> ```bash
> grep -A2 'microos_arm_snapshot' .terraform/modules/kube-hetzner/main.tf | grep with_architecture
> # must print: with_architecture = "x86"   (and NOT "arm")
> ```

## MicroOS snapshots (kube-hetzner prerequisite)

The module reads **unconditionally** an x86 snapshot AND an ARM snapshot
(`data.hcloud_image.microos_{x86,arm}_snapshot`), even if the cluster has no
ARM node. Built via Packer:
```bash
cd .terraform/modules/kube-hetzner/packer-template
HCLOUD_TOKEN=… packer build -only='hcloud.microos-x86-snapshot' hcloud-microos-snapshots.pkr.hcl
```
> The CX line was renamed (cx22→**cx23**): the upstream Packer template targets
> `cx22`, to be corrected to `cx23` for the x86 build.

### ARM patch (Ampere capacity unavailable) — ⚠️ recurring trap

At the initial setup, Hetzner's ARM capacity was exhausted (`resource_unavailable`
on cax11/cax21 × fsn1/nbg1/hel1), so **no ARM snapshot was built** — the project
only has an **x86** snapshot (`microos-snapshot=yes`, arch `x86`).

The module (v2.18.0) declares the ARM data source as a `data` block **without `count`**, so Terraform
**evaluates it on every plan/apply** even if the cluster is 100% x86 (its id is only read for a
`server_type` starting with `cax`, which we don't have). Without an ARM snapshot, this evaluation fails with
`no image found` and **blocks every plan/apply**. Hence the patch: force the ARM data source onto `x86`.

**The patch** (`.terraform/modules/kube-hetzner/main.tf`, data source `microos_arm_snapshot`):
```hcl
data "hcloud_image" "microos_arm_snapshot" {
  with_selector     = "microos-snapshot=yes"
  with_architecture = "x86"    # ← patched; the original is "arm"
  most_recent       = true
}
```

**What overwrites it**: it lives in the module cache `.terraform/modules/`, so it disappears on any
**module re-download** — i.e. `terraform init -upgrade`, **or** a `terraform init`
on a **fresh checkout** (no `.terraform/`). An ordinary `terraform init` over an existing `.terraform`
**leaves it untouched**. → **Do not run `init -upgrade`**; after a fresh checkout or
a deliberate upgrade, **re-apply the patch** (one line: `with_architecture` `arm`→`x86`) before
any apply.

**The `microos_{x86,arm}_snapshot_id` variables don't help**: in 2.18.0 they are declared but
not wired (the code references `data.hcloud_image.microos_arm_snapshot.id` directly), so
providing them does not avoid evaluating the data source.

**Decision (2026-07-15): we keep the patch.** Building an ARM snapshot just to satisfy an unused
data source adds more surface than the one-liner removes. **Build it only if we ever
add an ARM nodepool** (`cax…`) — at which point a real arm snapshot is needed anyway:
`packer build -only='hcloud.microos-arm-snapshot' …` then remove the patch (revert to `arm`).

## Control-plane HA (3 etcd members + LB)

`control_plane_nodepools` = **3 nodepools** (`control-plane`/nbg1, `control-plane-fsn`/fsn1,
`control-plane-hel`/hel1, count 1 each) → **etcd quorum 3, tolerates 1 CP failure**. `use_control_plane_lb
= true` places a **Hetzner LB** in front of the 3 apiservers → the API endpoint is the LB (the kubeconfig
points to the LB's IP), not a CP IP. Why 3 CP: the undersized control-plane throttled
the apiserver, which starved the Linkerd control-plane of its ability to serve new proxies
(meshed pods that wedge at boot) — 3 CP spread the watch load.

> **1→3 migration on a live cluster (done 2026-07-15)**: the plan must be **non-destructive** — it
> must only CREATE the 2 new CP + the LB, and **re-run** (replace of `null_resource`) the existing
> CP's config + the worker's agent; **no existing `hcloud_server`/volume destroyed** (check before
> apply: `grep hcloud_server /tmp/plan.txt | grep -iE 'destroyed|replaced'` must be empty).
>
> ⚠️ **Gotcha — the agent reconfig leaves the WORKER cordoned.** During the apply, k3s reconfigures
> the worker's agent and leaves it `unschedulable` (taint `node.kubernetes.io/unschedulable`) without
> uncordoning it → **all app pods go `Pending` → site down**. Immediate fix:
> `kubectl uncordon k3s-worker-zez`. The Traefik pod (RWO acme.json volume) then takes ~30-60 s to
> reattach its volume before serving. **Plan for a short outage window** for this kind of
> control-plane migration.

## Destroy
```bash
terraform destroy
```
> The Postgres data lives on a CSI volume: a `destroy` deletes it. Verify a recent S3
> backup exists (Plan 5) before any destroy.
