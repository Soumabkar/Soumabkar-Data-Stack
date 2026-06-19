#!/usr/bin/env bash
# ============================================================================
# provision-data-stack.sh  v2.1
# Provisionnement complet de la VM data-stack
# Stack : MinIO + Hive Metastore + Trino + Airflow + dbt
#
# Améliorations vs v1 :
#   - set -euo pipefail  (arrêt sur toute erreur / variable non définie)
#   - Logging horodaté
#   - Vérifications idempotentes à chaque étape
#   - Gestion du groupe docker sans newgrp (sg docker)
#   - Health-check Trino avant de lancer le pipeline
#   - Support du flag --skip-data pour ignorer le chargement initial
# ============================================================================
set -euo pipefail

# ---------- Configuration ---------------------------------------------------
REPO_URL="https://github.com/Soumabkar/Soumabkar-Data-Stack.git"
PROJECT_DIR="${HOME}/Soumabkar-Data-Stack"
# Dossier contenant le compose ET le build context (Dockerfile-hive, hive-site.xml, trino-config/)
SERVICE_DIR="${PROJECT_DIR}/Provisions-Files/docker/dockerfile/Service_MinIO_Trino_Hive"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose-datalake.yml"
DBT_DIR="${HOME}/dbt"
SKIP_DATA="${1:-}"   # passer --skip-data pour ignorer le pipeline

# ---------- Helpers ---------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }

# ---------- 1. Mise à jour système ------------------------------------------
log "=== [1/8] Mise à jour système ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
ok "Système à jour"

# ---------- 2. Paquets de base ----------------------------------------------
log "=== [2/8] Paquets de base ==="
sudo apt-get install -y -qq \
  git curl wget \
  python3 python3-pip python3-venv \
  openjdk-17-jdk \
  ca-certificates gnupg \
  net-tools        # pour le healthcheck hive (netstat)
ok "Paquets installés"

# ---------- 3. JAVA_HOME ----------------------------------------------------
log "=== [3/8] JAVA_HOME ==="
JAVA_EXPORT='export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64'
PATH_EXPORT='export PATH=$JAVA_HOME/bin:$PATH'
grep -qxF "$JAVA_EXPORT" ~/.bashrc || echo "$JAVA_EXPORT" >> ~/.bashrc
grep -qxF "$PATH_EXPORT" ~/.bashrc || echo "$PATH_EXPORT" >> ~/.bashrc
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
ok "JAVA_HOME configuré → $(java -version 2>&1 | head -1)"

# ---------- 4. Docker -------------------------------------------------------
log "=== [4/8] Docker ==="
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  ok "Docker installé"
else
  ok "Docker déjà présent → $(docker --version)"
fi

# Ajouter l'utilisateur au groupe docker (idempotent)
if ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER"
  log "  Groupe docker ajouté — les commandes docker utilisent 'sg docker'"
fi

# ---------- 5. Clone / mise à jour du projet --------------------------------
log "=== [5/8] Clone / mise à jour du projet ==="
if [ ! -d "$PROJECT_DIR" ]; then
  git clone "$REPO_URL" "$PROJECT_DIR"
  ok "Dépôt cloné → $PROJECT_DIR"
else
  git -C "$PROJECT_DIR" pull
  ok "Dépôt mis à jour"
fi

# ---------- 6. Environnement dbt --------------------------------------------
log "=== [6/8] Environnement dbt ==="
mkdir -p "$DBT_DIR"
cd "$DBT_DIR"

# dbt-trino requiert Python 3.8-3.12 (incompatible avec Python 3.13+)
# Si le système a Python 3.13+, installer Python 3.12 via deadsnakes PPA
PYTHON_BIN="python3"
PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')

if [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -ge 13 ]; then
  log "  Python 3.${PY_MINOR} détecté — dbt-trino nécessite Python ≤ 3.12"
  # Ubuntu 25.10 (resolute) fournit python3.12 nativement — pas besoin du PPA
  # Le PPA deadsnakes ne fournit PAS python3.12-distutils sur resolute
  if apt-cache show python3.12 &>/dev/null 2>&1; then
    log "  python3.12 disponible nativement (Ubuntu ≥ 25.10)"
    sudo apt-get install -y -qq python3.12 python3.12-venv
  else
    log "  Installation via deadsnakes PPA..."
    sudo apt-get install -y -qq software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update -qq
    sudo apt-get install -y -qq python3.12 python3.12-venv
  fi
  PYTHON_BIN="python3.12"
  ok "Python 3.12 prêt → $($PYTHON_BIN --version)"
else
  ok "Python 3.${PY_MINOR} compatible avec dbt-trino"
fi

# Supprimer le venv existant s'il a été créé avec le mauvais Python
if [ -d dbt-venv ]; then
  VENV_PYTHON=$(dbt-venv/bin/python3 --version 2>/dev/null | grep -o "3\.[0-9]*" | head -1)
  TARGET_PYTHON=$($PYTHON_BIN --version 2>/dev/null | grep -o "3\.[0-9]*" | head -1)
  if [ "$VENV_PYTHON" != "$TARGET_PYTHON" ]; then
    log "  venv existant Python $VENV_PYTHON ≠ cible $TARGET_PYTHON — recréation"
    rm -rf dbt-venv
  fi
fi

if [ ! -d dbt-venv ]; then
  $PYTHON_BIN -m venv dbt-venv
  ok "venv créé (via $PYTHON_BIN)"
fi

# shellcheck source=/dev/null
source "$DBT_DIR/dbt-venv/bin/activate"
pip install --upgrade pip -q
pip install dbt-trino -q
ok "dbt-trino installé → $(dbt --version 2>&1 | head -1)"

if [ ! -d "$DBT_DIR/lakehouse_project" ]; then
  dbt init lakehouse_project --skip-profile-setup
fi

mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << 'EOF'
lakehouse_project:
  target: dev
  outputs:
    dev:
      type: trino
      method: none
      user: dbt
      host: localhost
      port: 8080
      database: hive
      schema: ecommerce
      threads: 4
EOF
ok "profiles.yml déployé"
deactivate

# ---------- 6b. Venv du pipeline Python (MinIO) -----------------------------
# Le pipeline Python (Provisions-Files/project/python/MinIO) a son propre venv.
# Il doit aussi utiliser Python 3.12 — pandas 2.1.4 ne compile pas sur Python 3.14.
PIPELINE_DIR="${PROJECT_DIR}/Provisions-Files/project/python/MinIO"
if [ -d "$PIPELINE_DIR" ]; then
  log "=== [6b] Venv pipeline Python ==="
  cd "$PIPELINE_DIR"

  # Supprimer si créé avec le mauvais Python
  if [ -d venv ]; then
    VENV_MINOR=$(venv/bin/python3 -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "99")
    if [ "$VENV_MINOR" -ge 13 ]; then
      log "  venv pipeline Python 3.${VENV_MINOR} → recréation avec python3.12"
      rm -rf venv
    fi
  fi

  if [ ! -d venv ]; then
    $PYTHON_BIN -m venv venv
    ok "venv pipeline créé (python3.12)"
  fi

  source venv/bin/activate
  pip install --upgrade pip -q
  pip install -r requirements.txt -q
  ok "Dépendances pipeline installées"
  deactivate
  cd "$PROJECT_DIR"
fi

# ---------- 7. Démarrage de la stack ----------------------------------------
log "=== [7/8] Démarrage de la stack Docker Compose ==="
# Stack actuelle : MinIO + Hive Metastore + Trino (Airflow retiré du compose principal)
# Build context : Service_MinIO_Trino_Hive/ (Dockerfile-hive + hive-site.xml + trino-config/)
cd "$PROJECT_DIR/Provisions-Files/docker/dockerfile/Service_MinIO_Trino_Hive"

sg docker -c "docker compose -f $COMPOSE_FILE up -d --build"
ok "Stack démarrée"

# Health-check Trino (max 120s)
log "  Attente Trino prêt..."
TRINO_UP=0
for i in $(seq 1 24); do
  if curl -sf http://localhost:8080/v1/info | grep -q '"starting":false'; then
    TRINO_UP=1
    break
  fi
  sleep 5
done
if [ "$TRINO_UP" -eq 0 ]; then
  log "  ⚠ Trino pas encore prêt après 120s — vérifiez : docker compose logs trino"
fi

# ---------- 8. Chargement des données + vérifications ----------------------
log "=== [8/8] Chargement des données initiales ==="

if [ "$SKIP_DATA" = "--skip-data" ]; then
  log "  → Ignoré (--skip-data)"
else
  PIPELINE_DIR="${PROJECT_DIR}/Provisions-Files/project/python/MinIO"
  if [ -f "$PIPELINE_DIR/pipeline.py" ]; then
    cd "$PIPELINE_DIR"
    source venv/bin/activate
    log "  Exécution pipeline.py..."
    python3 pipeline.py
    ok "Pipeline exécuté"
    deactivate
  else
    log "  ⚠ pipeline.py introuvable — ignorer ou vérifier le chemin"
  fi
fi

log "=== Statut containers ==="
sg docker -c "docker compose -f $COMPOSE_FILE ps"

# ---------- Résumé ----------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=============================================="
echo " data-stack prêt !"
echo "=============================================="
echo " MinIO    : http://${IP}:9001  (admin / [voir hive-site.xml])"
echo " Trino    : http://${IP}:8080"
echo ""
echo " dbt :"
echo "   cd ~/dbt/lakehouse_project"
echo "   source ~/dbt/dbt-venv/bin/activate"
echo "   dbt run && dbt test"
echo "=============================================="