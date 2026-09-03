# NFS Setup for Kubernetes ReadWriteMany Storage

This runbook configures an NFS server and Kubernetes worker nodes for a `ReadWriteMany` (`RWX`) PersistentVolume.

## Lab values used

- NFS server IP: `172.16.0.2`
- Kubernetes node subnet: `172.16.0.0/24`
- NFS export directory: `/srv/k8s-rwx`
- NFS version: `4.1`
- Kubernetes namespace: `rwx-lab`

> Change these values if your environment is different.

---

## 1. Network layout

```text
NFS server:       172.16.0.2
Worker node:      172.16.0.4 or another address in 172.16.0.0/24
NFS export:       172.16.0.2:/srv/k8s-rwx
Required port:    TCP 2049
```

---

## 2. Configure the NFS server on Ubuntu or Debian

Run this section on the machine at `172.16.0.2`.

### 2.1 Check the server address

```bash
hostname
hostname -I
ip -br address
```

Confirm that the machine owns the address `172.16.0.2`.

### 2.2 Install the NFS server package

```bash
sudo apt-get update
sudo apt-get install -y nfs-kernel-server
```

### 2.3 Create the exported directory

```bash
sudo mkdir -p /srv/k8s-rwx
sudo chown nobody:nogroup /srv/k8s-rwx
sudo chmod 0777 /srv/k8s-rwx
```

> `0777` is suitable for a temporary isolated lab. For production, use controlled Linux user and group ownership, pod security contexts, and more restrictive permissions.

### 2.4 Configure the NFS export

Create a dedicated exports file:

```bash
cat <<'EOF' | sudo tee /etc/exports.d/k8s-rwx.exports
/srv/k8s-rwx 172.16.0.0/24(rw,sync,no_subtree_check,root_squash)
EOF
```

The options mean:

- `rw`: allow reads and writes
- `sync`: confirm writes after the server commits them
- `no_subtree_check`: avoid subtree verification issues
- `root_squash`: prevent a root user on a client from automatically becoming root on the NFS server

### 2.5 Validate and activate the export

```bash
sudo exportfs -rav
sudo exportfs -v
```

Expected output should include `/srv/k8s-rwx` and `172.16.0.0/24`.

### 2.6 Start and enable the NFS server

```bash
sudo systemctl enable --now nfs-kernel-server
sudo systemctl restart nfs-kernel-server
sudo systemctl status nfs-kernel-server --no-pager -l
```

### 2.7 Confirm NFS is listening on TCP port 2049

```bash
sudo ss -lnt | grep ':2049'
```

Expected output is similar to:

```text
LISTEN 0 64 0.0.0.0:2049 0.0.0.0:*
LISTEN 0 64 [::]:2049    [::]:*
```

### 2.8 Check supported NFS versions

```bash
sudo cat /proc/fs/nfsd/versions
```

Confirm that `+4` and `+4.1` appear in the output.

Example:

```text
-2 +3 +4 +4.1 +4.2
```

### 2.9 Check RPC registration

```bash
sudo rpcinfo -p localhost
```

Look for an NFS service entry using TCP port `2049`.

---

## 3. Firewall configuration on the NFS server

Use the section matching your firewall.

### 3.1 Ubuntu UFW

Check the current status:

```bash
sudo ufw status verbose
```

Allow NFSv4 traffic only from the Kubernetes node subnet:

```bash
sudo ufw allow from 172.16.0.0/24 to any port 2049 proto tcp
sudo ufw reload
sudo ufw status numbered
```

### 3.2 RHEL-family firewalld

```bash
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --reload
sudo firewall-cmd --list-services
```

For NFSv3, `mountd` and `rpc-bind` may also be required:

```bash
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload
```

> If the machines run in a cloud or virtualized network, also check security groups, network ACLs, and hypervisor firewall rules.

---

## 4. RHEL, Rocky Linux, AlmaLinux, or CentOS NFS server

Use this section instead of Section 2 if the NFS server uses a RHEL-family operating system.

### 4.1 Install NFS packages

```bash
sudo dnf install -y nfs-utils
```

For an older operating system:

```bash
sudo yum install -y nfs-utils
```

### 4.2 Create the export directory

```bash
sudo mkdir -p /srv/k8s-rwx
sudo chown nobody:nobody /srv/k8s-rwx
sudo chmod 0777 /srv/k8s-rwx
```

### 4.3 Configure the export

```bash
cat <<'EOF' | sudo tee /etc/exports.d/k8s-rwx.exports
/srv/k8s-rwx 172.16.0.0/24(rw,sync,no_subtree_check,root_squash)
EOF
```

### 4.4 Start NFS and apply the export

```bash
sudo systemctl enable --now nfs-server
sudo exportfs -rav
sudo systemctl restart nfs-server
sudo systemctl status nfs-server --no-pager -l
sudo exportfs -v
sudo ss -lnt | grep ':2049'
```

---

## 5. Configure every Kubernetes worker node

Run this section on **every worker node** that may run a pod using the NFS volume.

### 5.1 Ubuntu or Debian workers

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
```

### 5.2 RHEL-family workers

```bash
sudo dnf install -y nfs-utils
```

### 5.3 Confirm the NFS mount helper exists

```bash
command -v mount.nfs
command -v mount.nfs4
ls -l /sbin/mount.nfs* /usr/sbin/mount.nfs* 2>/dev/null
```

---

## 6. Test network access from each worker node

### 6.1 Check basic IP reachability

```bash
ping -c 3 172.16.0.2
```

### 6.2 Check TCP port 2049

If Netcat is installed:

```bash
nc -vz 172.16.0.2 2049
```

Expected result:

```text
Connection to 172.16.0.2 2049 port [tcp/nfs] succeeded!
```

If Netcat is not installed:

```bash
timeout 3 bash -c '</dev/tcp/172.16.0.2/2049' \
  && echo 'Port 2049 reachable' \
  || echo 'Port 2049 failed'
```

Interpretation:

- `succeeded`: the NFS service is reachable
- `Connection refused`: the server is reachable, but NFS is not listening or a firewall is rejecting the connection
- `timed out`: a firewall or network rule is probably dropping the traffic
- `No route to host`: routing or interface configuration is incorrect

---

## 7. Manually mount the NFS share from every worker

Create a temporary mount point:

```bash
sudo mkdir -p /mnt/nfs-test
```

Mount with NFSv4.1:

```bash
sudo mount -v -t nfs -o hard,nfsvers=4.1 \
  172.16.0.2:/srv/k8s-rwx /mnt/nfs-test
```

Verify the mount:

```bash
findmnt /mnt/nfs-test
mount | grep nfs-test
```

Test writing:

```bash
echo "written by $(hostname) at $(date -Iseconds)" | \
  sudo tee "/mnt/nfs-test/test-$(hostname).txt"
```

Test reading:

```bash
ls -la /mnt/nfs-test
cat "/mnt/nfs-test/test-$(hostname).txt"
```

Unmount after the test:

```bash
sudo umount /mnt/nfs-test
```

Repeat this test from at least two different Kubernetes worker nodes.

---

## 8. Kubernetes static NFS PersistentVolume

Create `01-nfs-pv.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: rwx-nfs-pv
  labels:
    lab: rwx-nfs
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: nfs-static
  mountOptions:
    - hard
    - nfsvers=4.1
  nfs:
    server: 172.16.0.2
    path: /srv/k8s-rwx
```

Apply it:

```bash
kubectl apply -f 01-nfs-pv.yaml
kubectl get pv rwx-nfs-pv
```

---

## 9. Kubernetes ReadWriteMany PersistentVolumeClaim

Create the namespace:

```bash
kubectl create namespace rwx-lab
```

Create `02-nfs-pvc.yaml`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rwx-nfs-claim
  namespace: rwx-lab
spec:
  accessModes:
    - ReadWriteMany
  volumeMode: Filesystem
  storageClassName: nfs-static
  resources:
    requests:
      storage: 5Gi
  selector:
    matchLabels:
      lab: rwx-nfs
```

Apply and verify:

```bash
kubectl apply -f 02-nfs-pvc.yaml
kubectl get pv
kubectl get pvc -n rwx-lab
```

The PV and PVC should show `Bound`, and access mode should show `RWX`.

---

## 10. Verify Kubernetes pods after fixing NFS

Watch the pods:

```bash
kubectl get pods -n rwx-lab -o wide -w
```

Kubelet normally retries a failed mount automatically. If an old pod remains stuck, delete it and let the Deployment replace it:

```bash
kubectl delete pod <stuck-pod-name> -n rwx-lab
```

Check recent events:

```bash
kubectl get events -n rwx-lab --sort-by=.lastTimestamp
```

Inspect a specific pod:

```bash
kubectl describe pod <pod-name> -n rwx-lab
```

Confirm pods run on different nodes:

```bash
kubectl get pods -n rwx-lab -o wide
```

Read the shared log from one writer pod:

```bash
POD=$(kubectl get pods -n rwx-lab \
  -l app=rwx-writer \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n rwx-lab "$POD" -- tail -n 30 /shared/concurrent.log
```

---

## 11. Troubleshooting commands

### Error: `bad option` or missing mount helper

Typical message:

```text
bad option; ... you might need a /sbin/mount.<type> helper program
```

Fix on the affected Ubuntu or Debian worker:

```bash
sudo apt-get update
sudo apt-get install -y nfs-common
```

Fix on a RHEL-family worker:

```bash
sudo dnf install -y nfs-utils
```

### Error: `Connection refused`

Run on the NFS server:

```bash
sudo systemctl status nfs-kernel-server --no-pager -l
sudo systemctl restart nfs-kernel-server
sudo ss -lnt | grep ':2049'
sudo exportfs -v
sudo journalctl -u nfs-kernel-server -n 100 --no-pager
```

For RHEL-family servers, replace `nfs-kernel-server` with `nfs-server`.

Run from the affected worker:

```bash
nc -vz 172.16.0.2 2049
```

### Error: `access denied by server`

Run on the NFS server:

```bash
cat /etc/exports
cat /etc/exports.d/k8s-rwx.exports
sudo exportfs -rav
sudo exportfs -v
```

Confirm the worker address is in the permitted subnet:

```bash
hostname -I
ip -br address
```

### Error: NFSv4.1 is unsupported

Check the server:

```bash
sudo cat /proc/fs/nfsd/versions
```

Try NFSv4:

```bash
sudo mount -v -t nfs -o hard,vers=4 \
  172.16.0.2:/srv/k8s-rwx /mnt/nfs-test
```

Try NFSv3 only as an isolation test:

```bash
sudo mount -v -t nfs -o hard,vers=3 \
  172.16.0.2:/srv/k8s-rwx /mnt/nfs-test
```

If only NFSv3 works, additional RPC services and firewall ports may be required. Update the Kubernetes PV to `nfsvers=3` only after proving that NFSv4.1 cannot be used.

### Check server logs

Ubuntu or Debian:

```bash
sudo journalctl -u nfs-kernel-server -n 100 --no-pager
sudo journalctl -k -n 100 --no-pager
```

RHEL family:

```bash
sudo journalctl -u nfs-server -n 100 --no-pager
sudo journalctl -k -n 100 --no-pager
```

### Check worker kubelet logs

```bash
sudo journalctl -u kubelet -n 100 --no-pager
```

---

## 12. Quick Ubuntu/Debian setup

### Run on NFS server `172.16.0.2`

```bash
sudo apt-get update
sudo apt-get install -y nfs-kernel-server

sudo mkdir -p /srv/k8s-rwx
sudo chown nobody:nogroup /srv/k8s-rwx
sudo chmod 0777 /srv/k8s-rwx

cat <<'EOF' | sudo tee /etc/exports.d/k8s-rwx.exports
/srv/k8s-rwx 172.16.0.0/24(rw,sync,no_subtree_check,root_squash)
EOF

sudo exportfs -rav
sudo systemctl enable --now nfs-kernel-server
sudo systemctl restart nfs-kernel-server

sudo exportfs -v
sudo ss -lnt | grep ':2049'
sudo cat /proc/fs/nfsd/versions
```

If UFW is enabled:

```bash
sudo ufw allow from 172.16.0.0/24 to any port 2049 proto tcp
sudo ufw reload
```

### Run on every Ubuntu/Debian Kubernetes worker

```bash
sudo apt-get update
sudo apt-get install -y nfs-common

nc -vz 172.16.0.2 2049

sudo mkdir -p /mnt/nfs-test
sudo mount -v -t nfs -o hard,nfsvers=4.1 \
  172.16.0.2:/srv/k8s-rwx /mnt/nfs-test

echo "written by $(hostname) at $(date -Iseconds)" | \
  sudo tee "/mnt/nfs-test/test-$(hostname).txt"

ls -la /mnt/nfs-test
sudo umount /mnt/nfs-test
```

---

## 13. Success checklist

- [ ] `172.16.0.2` is the correct NFS server address.
- [ ] NFS server package is installed.
- [ ] NFS service is active.
- [ ] TCP port `2049` is listening.
- [ ] `/srv/k8s-rwx` exists.
- [ ] The export permits `172.16.0.0/24`.
- [ ] `exportfs -v` displays the export.
- [ ] NFS client package is installed on every worker.
- [ ] Port `2049` is reachable from every worker.
- [ ] Manual NFSv4.1 mount succeeds from every worker.
- [ ] A file written from one worker is visible from another.
- [ ] Kubernetes PV and PVC are `Bound`.
- [ ] Writer pods reach `Running` status.
- [ ] Writer pods are placed on different nodes.
- [ ] The shared log contains entries from multiple pods and nodes.

---

## 14. Cleanup of the manual test mount

Run on each worker if required:

```bash
sudo umount /mnt/nfs-test 2>/dev/null || true
sudo rmdir /mnt/nfs-test 2>/dev/null || true
```

Do not delete `/srv/k8s-rwx` until you have confirmed that no Kubernetes workload still needs its data.
