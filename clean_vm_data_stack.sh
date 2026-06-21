#!/usr/bin/env bash
# ============================================================================
# clean_vm_data_stack.sh  v2.0
# Nettoyage complet de la VM data-stack
#   - Arrêt + suppression containers, volumes, images
#   - Suppression dossiers projet, dbt, venvs, logs
# Idempotent : peut être lancé même si certains éléments n'existent plus.
# ============================================================================
set -uo pipefail   # PAS de -e : on veut continuer même si un élément manque

log() { echo "[$(date '+%H:%M:%S')] $*"; }

PROJECT_DIR="${HOME}/Soumabkar-Data-Stack"
SERVICE_DIR="${PROJECT_DIR}/Provisions-Files/docker/dockerfile/Service_MinIO_Trino_Hive"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose-datalake.yml"

# ---------- 1. Arrêt propre via compose (si présent) ------------------------
log "=== [1/6] Arrêt de la stack via compose ==="
if [ -f "$COMPOSE_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
  log "  compose down effectué"
else
  log "  compose introuvable — arrêt direct par nom de container"
fi

# ---------- 2. Arrêt direct des containers (fallback) -----------------------
log "=== [2/6] Suppression containers résiduels ==="
for c in airflow trino hive-metastore metastore-db minio; do
  docker stop "$c" 2>/dev/null && log "  stop $c" || true
  docker rm   "$c" 2>/dev/null && log "  rm   $c" || true
done

# ---------- 3. Suppression des volumes --------------------------------------
log "=== [3/6] Suppression des volumes ==="
VOLS=$(docker volume ls -q 2>/dev/null)
if [ -n "$VOLS" ]; then
  docker volume rm $VOLS 2>/dev/null || true
  log "  volumes supprimés"
else
  log "  aucun volume"
fi

# ---------- 4. Suppression des images ---------------------------------------
log "=== [4/6] Suppression des images ==="
for img in \
  service_minio_trino_hive-hive-metastore:latest \
  service_minio_trino_hive-airflow:latest \
  trinodb/trino:466 \
  postgres:15 \
  minio/minio:latest \
  apache/airflow:2.10.4-python3.12; do
  docker rmi "$img" 2>/dev/null && log "  rmi $img" || true
done

# ---------- 5. Nettoyage global Docker --------------------------------------
log "=== [5/6] Nettoyage global (build cache, dangling) ==="
docker system prune -af --volumes || true

# ---------- 6. Suppression dossiers + fichiers ------------------------------
log "=== [6/6] Suppression dossiers et logs ==="
rm -rf "${HOME}/Soumabkar-Data-Stack"
rm -rf "${HOME}/dbt"
rm -rf "${HOME}/dbt-lakehouse" "${HOME}/dbt-lakehouse-models.zip" "${HOME}/dbt-lakehouse-project.zip"
rm -f  "${HOME}/provision.log" "${HOME}/deploy.log" "${HOME}/pipeline.log"
rm -rf "${HOME}/.ivy2"          # cache Spark/Ivy
log "  dossiers supprimés"

# ---------- Vérification ----------------------------------------------------
echo ""
echo "=============================================="
echo " Nettoyage terminé — état :"
echo "=============================================="
echo "Containers :"; docker ps -a --format "  {{.Names}} ({{.Status}})" || echo "  aucun"
echo "Images :";     docker images --format "  {{.Repository}}:{{.Tag}}" || echo "  aucune"
echo "Volumes :";    docker volume ls -q | sed 's/^/  /' || echo "  aucun"
echo "Home :";       ls "${HOME}" | sed 's/^/  /'
echo "=============================================="