#!/usr/bin/env bash
#
# nfs-setup.sh — install & configure the NFS server, or verify NFS-client
# readiness on a Kubernetes node.
#
# Usage:
#   ./nfs-setup.sh server                 # run ON the NFS server (172.16.0.5)
#   ./nfs-setup.sh client [server_ip]     # run ON each k8s node (master + workers)
#
set -euo pipefail

MODE="${1:-}"
NFS_SERVER_IP="${2:-172.16.0.5}"
CLIENT_SUBNET="172.16.0.0/24"
EXPORT_DIRS=("/srv/k8s-rwx" "/opt/sonar")

usage() {
  echo "Usage: $0 {server|client} [nfs_server_ip]"
  echo "  server  - installs nfs-kernel-server, creates & exports the shares"
  echo "  client  - installs nfs-common and verifies mount access to the server"
  exit 1
}

[[ "$MODE" == "server" || "$MODE" == "client" ]] || usage

# --------------------------------------------------------------------------
if [[ "$MODE" == "server" ]]; then

  echo "==> Installing nfs-kernel-server..."
  sudo apt-get update
  sudo apt-get install -y nfs-kernel-server

  echo "==> Creating export directories..."
  sudo mkdir -p /srv/k8s-rwx
  sudo mkdir -p /opt/sonar/{postgresql,sonarqube-data,sonarqube-extensions,sonarqube-logs,nexus-data}

  echo "==> Setting ownership & permissions..."
  sudo chown -R nobody:nogroup "${EXPORT_DIRS[@]}"
  sudo chmod -R 777 "${EXPORT_DIRS[@]}"

  echo "==> Writing /etc/exports.d/k8s-rwx.exports..."
  sudo mkdir -p /etc/exports.d
  {
    for DIR in "${EXPORT_DIRS[@]}"; do
      echo "${DIR} ${CLIENT_SUBNET}(rw,sync,no_subtree_check,root_squash)"
    done
  } | sudo tee /etc/exports.d/k8s-rwx.exports

  echo "==> Enabling & starting nfs-kernel-server..."
  sudo systemctl enable --now nfs-kernel-server

  echo "==> Applying and verifying exports..."
  sudo exportfs -rav
  sudo exportfs -v

  # Open the NFS ports to the cluster subnet if ufw is active
  if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
    echo "==> ufw is active — allowing NFS traffic from ${CLIENT_SUBNET}..."
    sudo ufw allow from "${CLIENT_SUBNET}" to any port nfs
    sudo ufw allow from "${CLIENT_SUBNET}" to any port 111
    sudo ufw allow from "${CLIENT_SUBNET}" to any port 2049
  fi

  echo "==> Service status:"
  sudo systemctl status nfs-kernel-server --no-pager

  echo
  echo "==> Done. Exported on ${NFS_SERVER_IP}: ${EXPORT_DIRS[*]}"

# --------------------------------------------------------------------------
elif [[ "$MODE" == "client" ]]; then

  echo "==> Installing nfs-common on $(hostname)..."
  sudo apt-get update
  sudo apt-get install -y nfs-common

  echo "==> Checking RPC/NFS reachability on ${NFS_SERVER_IP}..."
  rpcinfo -p "${NFS_SERVER_IP}" || echo "WARNING: rpcinfo failed — check network/firewall to ${NFS_SERVER_IP}"

  echo "==> Listing exports advertised by ${NFS_SERVER_IP}..."
  showmount -e "${NFS_SERVER_IP}" || echo "WARNING: showmount failed — server unreachable or exports not applied"

  TEST_DIR="/tmp/nfs-check-$$"
  mkdir -p "${TEST_DIR}"

  for DIR in "${EXPORT_DIRS[@]}"; do
    echo "---- Testing mount ${NFS_SERVER_IP}:${DIR} ----"
    if sudo mount -t nfs "${NFS_SERVER_IP}:${DIR}" "${TEST_DIR}"; then
      TEST_FILE="${TEST_DIR}/.nfs-check-$(hostname)-$$"
      if sudo touch "${TEST_FILE}" 2>/dev/null; then
        echo "Mount + write OK."
        sudo rm -f "${TEST_FILE}"
      else
        echo "WARNING: mounted but write failed (check root_squash / ownership)."
      fi
      sudo umount "${TEST_DIR}"
    else
      echo "WARNING: mount failed for ${DIR}"
    fi
  done

  rmdir "${TEST_DIR}" 2>/dev/null || true
  echo
  echo "==> NFS client check complete on $(hostname)."
fi
