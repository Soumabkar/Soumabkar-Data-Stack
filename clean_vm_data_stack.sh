#!/usr/bin/env bash
set -uo pipefail
log() { echo "[$(date '+%H:%M:%S')] $*"; }

PROJECT_DIR="${HOME}/Soumabkar-Data-Stack"
SERVICE_DIR="${PROJECT_DIR}/Provisions-Files/docker/dockerfile/Service_MinIO_Trino_Hive"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose-datalake.yml"

log "=== [1/6] Arrêt stack via compose ==="
if [ -f "$COMPOSE_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
else
  log "  compose introuvable — arrêt direct par nom"
fi

log "=== [2/6] Suppression containers ==="
for c in airflow trino hive-metastore metastore-db minio; do
  docker stop "$c" 2>/dev/null && log "  stop $c" || true
  docker rm   "$c" 2>/dev/null && log "  rm   $c" || true
done

log "=== [3/6] Suppression volumes ==="
VOLS=$(docker volume ls -q 2>/dev/null)
[ -n "$VOLS" ] && docker volume rm $VOLS 2>/dev/null || log "  aucun volume"

log "=== [4/6] Suppression images ==="
for img in \
  service_minio_trino_hive-hive-metastore:latest \
  service_minio_trino_hive-airflow:latest \
  trinodb/trino:466 postgres:15 minio/minio:latest \
  apache/airflow:2.10.4-python3.12 apache/hive:4.0.0; do
  docker rmi "$img" 2>/dev/null && log "  rmi $img" || true
done

log "=== [5/6] Nettoyage global ==="
docker system prune -af --volumes || true

log "=== [6/6] Suppression dossiers ==="
rm -rf "${HOME}/Soumabkar-Data-Stack" "${HOME}/dbt" "${HOME}/.ivy2"
rm -f  "${HOME}/provision.log" "${HOME}/deploy.log" "${HOME}/pipeline.log"

echo ""
echo "=============================================="
echo " Nettoyage terminé :"
echo "=============================================="
echo "Containers :"; docker ps -a --format "  {{.Names}}" || echo "  aucun"
echo "Images :";     docker images --format "  {{.Repository}}:{{.Tag}}"
echo "Home :";       ls "${HOME}"
echo "=============================================="
