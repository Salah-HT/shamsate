# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    k3s-server.sh                                      :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: shamsate <shamsate@student.1337.ma>        +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/06/11 15:42:19 by shamsate          #+#    #+#              #
#    Updated: 2026/06/11 15:44:05 by shamsate         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

export DEBIAN_FRONTEND=noninteractive

log() { echo "[k3s-server] $*"; }

if [[ $(id -u) -ne 0 ]]; then
	echo "This script must be run as root" >&2
	exit 1
fi

# Mise à jour rapide et utilitaires de base
log "Updating apt and installing prerequisites"
apt-get update
apt-get install -y curl net-tools

# Installation de K3s Server (Master) sur l'IP dédiée
log "Installing k3s server"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=192.168.56.110 --write-kubeconfig-mode 644" sh -s -

# Attendre que le jeton soit créé (avec timeout)
NODE_TOKEN=/var/lib/rancher/k3s/server/node-token
DEST_DIR=/vagrant
DEST_TOKEN="$DEST_DIR/node-token"

log "Waiting for node token at $NODE_TOKEN"
timeout=120
elapsed=0
interval=2
while [[ ! -f "$NODE_TOKEN" && $elapsed -lt $timeout ]]; do
	sleep $interval
	elapsed=$((elapsed + interval))
done

if [[ ! -f "$NODE_TOKEN" ]]; then
	echo "Timed out waiting for $NODE_TOKEN" >&2
	exit 1
fi

mkdir -p "$DEST_DIR"
install -m 0644 "$NODE_TOKEN" "$DEST_TOKEN"
log "Copied node token to $DEST_TOKEN"

log "Le Master K3s a été installé et configuré avec succès !"