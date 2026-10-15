#!/bin/bash
# EC2 #2 bootstrap: k3s (single-node Kubernetes) on Ubuntu 22.04
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- 2 GB swap: a 1 GB instance needs it to survive package installs and image builds ---
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

apt-get update -y
apt-get install -y curl

# Trimmed for 1 GB RAM: services use NodePorts, so Traefik and the service load balancer are not needed,
# and metrics-server is unused (Prometheus does the monitoring).
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik --disable servicelb --disable metrics-server --write-kubeconfig-mode 644" sh -

until k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 5; done
