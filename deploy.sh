#!/usr/bin/env bash
# ============================================================================
# deploy.sh — Bootstrap de déploiement data-stack v3.0
# Usage :
#   bash deploy.sh              # provisionnement complet
#   bash deploy.sh --skip-data  # stack Docker uniquement (sans pipeline ni dbt)
#
# Ce script :
#   1. Clone / met à jour le dépôt Soumabkar-Data-Stack
#   2. Donne les droits d'exécution à provision-data-stack.sh
#   3. Exécute provision-data-stack.sh (9 étapes)
# ============================================================================
set -euo pipefail

REPO_URL="https://github.com/Soumabkar/Soumabkar-Data-Stack.git"
REPO_DIR="${HOME}/Soumabkar-Data-Stack"
SKIP_DATA="${1:-}"

echo "[$(date '+%H:%M:%S')] === Bootstrap deploy.sh v3.0 ==="
echo "[$(date '+%H:%M:%S')] Repo : $REPO_URL"

# Clone ou mise à jour du dépôt
if [ -d "$REPO_DIR" ]; then
  echo "[$(date '+%H:%M:%S')] Dépôt existant — mise à jour..."
  git -C "$REPO_DIR" pull
  echo "[$(date '+%H:%M:%S')] Dépôt mis à jour → $REPO_DIR"
else
  echo "[$(date '+%H:%M:%S')] Clonage du dépôt..."
  git clone "$REPO_URL" "$REPO_DIR"
  echo "[$(date '+%H:%M:%S')] Dépôt cloné → $REPO_DIR"
fi

cd "$REPO_DIR"

echo "[$(date '+%H:%M:%S')] Droits d'exécution sur provision-data-stack.sh..."
chmod +x provision-data-stack.sh

echo "[$(date '+%H:%M:%S')] Lancement de provision-data-stack.sh $SKIP_DATA..."
bash provision-data-stack.sh "$SKIP_DATA" 2>&1 | tee ~/provision.log