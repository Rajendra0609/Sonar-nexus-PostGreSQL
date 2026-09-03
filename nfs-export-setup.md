# NFS Export Setup — `/opt/sonar`

Run these commands **on the NFS server (172.16.0.5)**, not on any Kubernetes
node. This creates the export directory structure used by the static PVs in
`k8s-nfs-persistentvolumes.yaml`.

---

## 1. Create the export directory and per-app subfolders

```bash
sudo mkdir -p /opt/sonar/{postgresql-data,sonarqube-data,sonarqube-extensions,sonarqube-logs,nexus-data}
```

## 2. Set ownership and permissions

```bash
sudo chown -R nobody:nogroup /opt/sonar
sudo chmod -R 777 /opt/sonar
```

> Permissive for now — the init containers in each pod `chown` their
> subfolder to the correct UID on first mount (`1000` for SonarQube, `200`
> for Nexus). You can tighten these permissions later once everything is
> confirmed running.

## 3. Install the NFS server package (if not already installed)

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y nfs-kernel-server

# RHEL/CentOS/Rocky
sudo yum install -y nfs-utils
```

## 4. Add the export

```bash
echo "/opt/sonar  172.16.0.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
```

> Replace `172.16.0.0/24` with the actual CIDR your Kubernetes nodes live
> on — or a specific node IP if you only have one.

## 5. Apply the export and restart the service

```bash
sudo exportfs -ra

# Ubuntu/Debian
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

# RHEL/CentOS/Rocky
sudo systemctl restart nfs-server
sudo systemctl enable nfs-server
```

## 6. Verify the export locally

```bash
sudo exportfs -v
```

You should see `/opt/sonar` listed with the subnet/host you allowed.

## 7. Verify reachability from a Kubernetes node

Run this from a **worker node**, not the NFS server:

```bash
showmount -e 172.16.0.5
```

`/opt/sonar` should appear in the output. Once confirmed, apply the static
PVs:

```bash
kubectl apply -f k8s-nfs-persistentvolumes.yaml
kubectl apply -f k8s-sonarqube-nexus-postgresql.yaml
kubectl get pv
kubectl get pvc -n devops-tools
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `showmount` fails / connection refused | Firewall blocking NFS ports | Allow `2049/tcp` (and `111/tcp+udp` for NFSv3) from the node subnet |
| `showmount` shows nothing | Export not applied | Re-run `sudo exportfs -ra`, check `/etc/exports` syntax |
| Pods stuck in `CrashLoopBackOff` with permission errors | Missing `no_root_squash` | Confirm it's present in the `/etc/exports` line, then `sudo exportfs -ra` |
| PVC stuck `Pending` after PVs applied | `claimRef` name/namespace mismatch, or PV/PVC size or accessMode mismatch | `kubectl describe pv <name>` and `kubectl describe pvc <name> -n devops-tools` |
