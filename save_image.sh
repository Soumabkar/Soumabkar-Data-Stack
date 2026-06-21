# Pull sur soumabkarserver
docker pull minio/minio:latest
docker pull postgres:15
docker pull trinodb/trino:466
docker pull apache/hive:4.0.0

# Puis exporter
docker save minio/minio:latest postgres:15 trinodb/trino:466 apache/hive:4.0.0 \
  | gzip > /tmp/data-stack-images.tar.gz