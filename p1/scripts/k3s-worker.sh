# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    k3s-worker.sh                                      :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: shamsate <shamsate@student.1337.ma>        +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/06/11 15:42:24 by shamsate          #+#    #+#              #
#    Updated: 2026/06/11 15:44:11 by shamsate         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive

log() { echo "[k3s-worker] $*"; }

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root" >&2
  exit 1
fi

log "Updating apt and installing prerequisites"
apt-get update
apt-get install -y curl net-tools

# Attente du token généré par le Master (avec timeout et diagnostics)
NODE_TOKEN=/vagrant/node-token
log "Checking /vagrant mount"
if ! mountpoint -q /vagrant; then
  log "/vagrant does not appear to be a mountpoint yet"
fi

log "Waiting for node token at $NODE_TOKEN"
timeout=300
elapsed=0
interval=3
while [[ $elapsed -lt $timeout ]]; do
  if [[ -f "$NODE_TOKEN" && -s "$NODE_TOKEN" ]]; then
    if [[ -r "$NODE_TOKEN" ]]; then
      break
    else
      log "Found $NODE_TOKEN but file is not readable by $(id -un). Showing permissions:"
      ls -l "$NODE_TOKEN" || true
    fi
  fi
  sleep $interval
  elapsed=$((elapsed + interval))
done

if [[ ! -f "$NODE_TOKEN" || ! -s "$NODE_TOKEN" ]]; then
  echo "Timed out waiting for a readable non-empty $NODE_TOKEN (waited ${timeout}s)" >&2
  log "Directory /vagrant listing for debugging:"
  ls -la /vagrant || true
  log "Mounts:"; mount | grep /vagrant || true
  exit 1
fi

# Read first non-empty line and trim trailing whitespace/newline
TOKEN=$(sed -n '1p' "$NODE_TOKEN" | tr -d '\r' | sed 's/[[:space:]]*$//')
if [[ -z "$TOKEN" ]]; then
  echo "Token file $NODE_TOKEN is empty after trimming" >&2
  ls -l "$NODE_TOKEN" || true
  head -n 5 "$NODE_TOKEN" || true
  exit 1
fi

log "Token read (first 8 chars): ${TOKEN:0:8}... len=${#TOKEN}"

log "Installing k3s agent and joining Master"
if ! curl -sfL https://get.k3s.io | K3S_URL="https://192.168.56.110:6443" K3S_TOKEN="$TOKEN" INSTALL_K3S_EXEC="--node-ip=192.168.56.111" sh -s -; then
  echo "k3s agent install failed" >&2
  exit 1
fi

log "Le Worker K3s a été installé et connecté au Master avec succès !"