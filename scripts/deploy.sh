#!/usr/bin/env bash
# Runs ON the application server (EC2 #2). Jenkins copies k8s/ and this script here, then runs:
#   bash deploy.sh <dockerhub-user>/devops-app:<tag>
set -euo pipefail

IMAGE="${1:?usage: deploy.sh <image:tag>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
K="sudo k3s kubectl"

$K apply -f "$DIR/k8s/00-namespace.yaml"

# Grafana mounts this ConfigMap, so it must exist before the Grafana Deployment is applied.
$K -n devops create configmap grafana-dashboards \
  --from-file="$DIR/k8s/dashboards" --dry-run=client -o yaml | $K apply -f -

for f in "$DIR"/k8s/[1-9]*.yaml; do
  sed "s|__IMAGE__|${IMAGE}|g" "$f" | $K apply -f -
done

echo "Waiting for rollout of ${IMAGE} ..."
if ! $K -n devops rollout status deployment/node-app --timeout=180s; then
  echo "Rollout failed - rolling back to the previous revision" >&2
  $K -n devops rollout undo deployment/node-app || true
  exit 1
fi
$K -n devops get pods -o wide
