# 1. Arrêter et supprimer tous les containers liés à la stack
cd ~/MinIO/Provisions-Files/docker/dockerfile/Service_MinIO_Trino_Hive
docker compose down -v --remove-orphans

# 2. Supprimer les images buildées localement
docker rmi $(docker images --filter "reference=hive-metastore*" -q) 2>/dev/null || true
docker rmi $(docker images --filter "reference=minio*" -q) 2>/dev/null || true

# 3. Nettoyage Docker global (images dangling, volumes orphelins, build cache)
docker system prune -af --volumes

# 4. Supprimer le dossier projet cloné
rm -rf ~/MinIO

# 5. Supprimer les venvs Python
rm -rf ~/dbt

# 6. Supprimer les logs et le script de provision
rm -f ~/provision.log ~/provision-data-stack.sh

# 7. Supprimer le cache Ivy/Spark
rm -rf ~/.ivy2

# 8. Vérification — doit tout être vide
docker ps -a
docker images
ls ~/