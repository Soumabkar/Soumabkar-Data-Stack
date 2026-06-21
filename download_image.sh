# Pull chaque image avec retry automatique, AVANT de lancer la stack
for img in minio/minio:latest postgres:15 trinodb/trino:466 apache/hive:4.0.0; do
  echo "=== Pull $img ==="
  for attempt in 1 2 3 4 5; do
    docker pull "$img" && break
    echo "Tentative $attempt échouée — retry dans 15s..."
    sleep 15
  done
done