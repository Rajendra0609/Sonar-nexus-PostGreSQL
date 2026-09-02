# NFS CSI Driver & StorageClass — Installation Guide

This guide covers installing the NFS CSI driver on a fresh Kubernetes cluster and
wiring it up to your NFS server, so the `nfs-storage` StorageClass used by
PostgreSQL / SonarQube / Nexus can actually provision volumes.

A `StorageClass` on its own does nothing — it just names a provisioner
(`nfs.csi.k8s.io`). Until the driver that implements that provisioner is
running in the cluster, every PVC that references the class will sit in
`Pending` forever. Steps 1–3 install that driver; step 4 applies the class.

---

## Prerequisites

- `kubectl` access to the cluster with admin/cluster-admin permissions
- Helm v3+ (recommended — a `kubectl`-only fallback is included)
- An NFS server already running, reachable from every node in the cluster
- The export path already created on the NFS server (e.g. `/opt/sonar`)

---

## 1. Verify the NFS export on the server

On the NFS server itself:

```bash
cat /etc/exports
```

You should see a line like:

```
/opt/sonar  172.16.0.0/24(rw,sync,no_subtree_check,no_root_squash)
```

If it's missing, add it and reload:

```bash
sudo mkdir -p /opt/sonar
echo "/opt/sonar  172.16.0.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

> **Note on `no_root_squash`:** the init containers in the app manifests run
> `chown` as root to fix volume ownership before the main app starts. Without
> `no_root_squash`, that write will silently fail and pods will crash-loop
> with permission errors.

From a Kubernetes **node** (not the NFS server), confirm the export is visible:

```bash
showmount -e 172.16.0.5
```

---

## 2. Install the NFS CSI driver

### Option A — Helm (recommended)

```bash
helm repo add csi-driver-nfs https://kubernetes-csi.github.io/csi-driver-nfs
helm repo update

helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --version 4.13.4
```

### Option B — kubectl only (no Helm)

```bash
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/install-driver.sh \
  | bash -s master --
```

---

## 3. Verify the driver is running

```bash
kubectl -n kube-system get pods -l app=csi-nfs-controller
kubectl -n kube-system get pods -l app=csi-nfs-node
```

Expected: **one** controller pod, and **one node pod per worker node**, all
`Running`. If any node pod is missing, that node won't be able to mount NFS
volumes for pods scheduled on it.

---

## 4. Apply the StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-storage
provisioner: nfs.csi.k8s.io
parameters:
  server: 172.16.0.5      # your NFS server IP/hostname
  share: /opt/sonar        # your NFS export path
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
```

```bash
kubectl apply -f nfs-storageclass.yaml
```

Confirm it registered:

```bash
kubectl get storageclass
```

---

## 5. Smoke-test with a throwaway PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-test-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: nfs-storage
  resources:
    requests:
      storage: 1Gi
```

```bash
kubectl apply -f nfs-test-pvc.yaml
kubectl get pvc nfs-test-pvc
```

It should flip to `Bound` within a few seconds. Once confirmed, clean it up:

```bash
kubectl delete -f nfs-test-pvc.yaml
```

---

## Troubleshooting

| Symptom | Likely cause | Check |
|---|---|---|
| PVC stuck `Pending` | Driver not installed / not ready | `kubectl describe pvc <name>` for events |
| PVC stuck `Pending` | Node can't reach NFS server | `ping`/`showmount -e` from a node |
| Pod stuck in permission errors | Missing `no_root_squash` on export | Re-check `/etc/exports` on the NFS server |
| `csi-nfs-node` pod `CrashLoopBackOff` | Missing NFS kernel client support on node OS | `lsmod \| grep nfs`, install `nfs-common` (Debian/Ubuntu) or `nfs-utils` (RHEL) on the node |
| StorageClass shows in `kubectl get sc` but PVCs still pending | Typo in `provisioner` name, or driver installed in wrong namespace | `kubectl get pods -n kube-system \| grep nfs` |

---

## Uninstalling the driver (if needed)

```bash
# Helm
helm uninstall csi-driver-nfs -n kube-system

# kubectl-only install
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/uninstall-driver.sh \
  | bash -s master --
```
