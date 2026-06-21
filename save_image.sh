# Sur soumabkarserver (hôte) — les images y sont peut-être déjà
docker save minio/minio:latest postgres:15 trinodb/trino:466 apache/hive:4.0.0 \
  | gzip > /tmp/data-stack-images.tar.gz

# Transférer vers la VM
scp /tmp/data-stack-images.tar.gz soumabkar@192.168.122.147:~/

# Sur la VM — charger les images localement
docker load < ~/data-stack-images.tar.gz