#!/usr/bin/env bash
# ============================================================================
# deploy.sh — Bootstrap de déploiement data-stack
# Usage : bash deploy.sh
#
# Ce script :
#   1. Clone le dépôt Soumabkar-Data-Stack
#   2. Se place à la racine du dépôt
#   3. Donne les droits d'exécution à provision-data-stack.sh
#   4. Exécute provision-data-stack.sh
# ============================================================================
set -euo pipefail

REPO_URL="https://github.com/Soumabkar/Soumabkar-Data-Stack.git"
REPO_DIR="${HOME}/Soumabkar-Data-Stack"

echo "[$(date '+%H:%M:%S')] Clonage du dépôt..."
if [ -d "$REPO_DIR" ]; then
  git -C "$REPO_DIR" pull
  echo "[$(date '+%H:%M:%S')] Dépôt mis à jour → $REPO_DIR"
else
  git clone "$REPO_URL" "$REPO_DIR"
  echo "[$(date '+%H:%M:%S')] Dépôt cloné → $REPO_DIR"
fi

cd "$REPO_DIR"

echo "[$(date '+%H:%M:%S')] Droits d'exécution sur provision-data-stack.sh..."
chmod +x provision-data-stack.sh

echo "[$(date '+%H:%M:%S')] Lancement de provision-data-stack.sh..."
bash provision-data-stack.sh 2>&1 | tee ~/provision.log