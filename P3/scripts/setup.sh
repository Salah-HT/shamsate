#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

log() { echo "[p3-setup] $*"; }

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ── Install dependencies ──
log "Updating apt"
apt-get update -qq

log "Installing curl, git, docker.io"
apt-get install -y -qq curl git docker.io net-tools

# ── Install k3d ──
if ! command -v k3d &>/dev/null; then
  log "Installing k3d"
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

log "k3d version: $(k3d version | head -1)"

# ── Install kubectl ──
if ! command -v kubectl &>/dev/null; then
  log "Installing kubectl"
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
fi

log "kubectl version: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

# ── Create k3d cluster ──
CLUSTER_NAME="inception-iot"
if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  log "Cluster $CLUSTER_NAME already exists, skipping creation"
else
  log "Creating k3d cluster: $CLUSTER_NAME"
  k3d cluster create "$CLUSTER_NAME" \
    --api-port 6443 \
    --port "8081:80@loadbalancer" \
    --agents 1
fi

# ── Wait for cluster readiness ──
log "Waiting for cluster nodes to be ready"
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# ── Create namespaces ──
log "Creating namespaces: argocd, dev"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# ── Install ArgoCD ──
log "Installing ArgoCD in namespace argocd"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log "Waiting for ArgoCD pods to be ready"
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s

# ── Install ArgoCD CLI ──
if ! command -v argocd &>/dev/null; then
  log "Installing argocd CLI"
  curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  chmod +x /usr/local/bin/argocd
fi

log "argocd CLI version: $(argocd version --client 2>/dev/null | head -1)"

# ── Get ArgoCD admin password ──
log "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(password will be available shortly, check later with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"

# ── Apply ArgoCD Application ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P3_DIR="$(dirname "$SCRIPT_DIR")"
APP_MANIFEST="$P3_DIR/confs/argocd-app.yaml"
if [ ! -f "$APP_MANIFEST" ]; then
  APP_MANIFEST="/vagrant/confs/argocd-app.yaml"
fi
if [ -f "$APP_MANIFEST" ]; then
  log "Applying ArgoCD Application manifest: $APP_MANIFEST"
  kubectl apply -f "$APP_MANIFEST"
else
  log "WARNING: argocd-app.yaml not found — you'll need to apply it manually after configuring the repo URL"
fi

# ── Print summary ──
log "══════════════════════════════════════════════"
log "P3 setup complete!"
log "ArgoCD UI: http://localhost:8081/argocd"
log "  user: admin"
log "  pass: retrieve with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
log ""
log "To access the app after sync:"
log "  kubectl port-forward svc/wil-playground -n dev 8888:8888"
log "  curl http://localhost:8888"
log "══════════════════════════════════════════════"
