#!/usr/bin/env bash
# ============================================================================
# provision-data-stack.sh  v3.0
# Provisionnement complet de la VM data-stack
# Stack : MinIO + Hive Metastore + Trino + dbt
#
# Nouveautés v3.0 vs v2.1 :
#   - Intégration dbt complète (modèles staging + marts depuis le repo)
#   - Création du schéma Hive avec la bonne location (s3a://datalake/)
#   - dbt run + dbt test automatiques après le pipeline
#   - Étapes numérotées sur 9 (ajout étape dbt)
# ============================================================================
set -euo pipefail

# ---------- Configuration ---------------------------------------------------
REPO_URL="https://github.com/Soumabkar/Soumabkar-Data-Stack.git"
PROJECT_DIR="${HOME}/Soumabkar-Data-Stack"
SERVICE_DIR="${PROJECT_DIR}/Provisions-Files/docker/dockerfile/Service_MinIO_Trino_Hive"
COMPOSE_FILE="${SERVICE_DIR}/docker-compose-datalake.yml"
DBT_DIR="${HOME}/dbt"
DBT_PROJECT="${DBT_DIR}/lakehouse_project"
SKIP_DATA="${1:-}"   # --skip-data pour ignorer pipeline + dbt

# ---------- Helpers ---------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }

# ---------- 1. Mise à jour système ------------------------------------------
log "=== [1/9] Mise à jour système ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
ok "Système à jour"

# ---------- 2. Paquets de base ----------------------------------------------
log "=== [2/9] Paquets de base ==="
sudo apt-get install -y -qq \
  git curl wget \
  python3 python3-pip python3-venv \
  openjdk-17-jdk \
  ca-certificates gnupg \
  net-tools
ok "Paquets installés"

# ---------- 3. JAVA_HOME ----------------------------------------------------
log "=== [3/9] JAVA_HOME ==="
JAVA_EXPORT='export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64'
PATH_EXPORT='export PATH=$JAVA_HOME/bin:$PATH'
grep -qxF "$JAVA_EXPORT" ~/.bashrc || echo "$JAVA_EXPORT" >> ~/.bashrc
grep -qxF "$PATH_EXPORT" ~/.bashrc || echo "$PATH_EXPORT" >> ~/.bashrc
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
ok "JAVA_HOME configuré → $(java -version 2>&1 | head -1)"

# ---------- 4. Docker -------------------------------------------------------
log "=== [4/9] Docker ==="
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  ok "Docker installé"
else
  ok "Docker déjà présent → $(docker --version)"
fi

if ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER"
  log "  Groupe docker ajouté — les commandes docker utilisent 'sg docker'"
fi

# ---------- 5. Clone / mise à jour du projet --------------------------------
log "=== [5/9] Clone / mise à jour du projet ==="
if [ ! -d "$PROJECT_DIR" ]; then
  git clone "$REPO_URL" "$PROJECT_DIR"
  ok "Dépôt cloné → $PROJECT_DIR"
else
  git -C "$PROJECT_DIR" pull
  ok "Dépôt mis à jour"
fi

# ---------- 6. Python 3.12 + venv dbt ---------------------------------------
log "=== [6/9] Environnement dbt ==="

# dbt-trino requiert Python ≤ 3.12 (incompatible Python 3.13+)
PYTHON_BIN="python3"
PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info.major)')

if [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -ge 13 ]; then
  log "  Python 3.${PY_MINOR} détecté — dbt-trino nécessite Python ≤ 3.12"
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

mkdir -p "$DBT_DIR"
cd "$DBT_DIR"

# Supprimer le venv si mauvaise version Python
if [ -d dbt-venv ]; then
  VENV_PYTHON=$(dbt-venv/bin/python3 --version 2>/dev/null | grep -o "3\.[0-9]*" | head -1)
  TARGET_PYTHON=$($PYTHON_BIN --version 2>/dev/null | grep -o "3\.[0-9]*" | head -1)
  if [ "$VENV_PYTHON" != "$TARGET_PYTHON" ]; then
    log "  venv Python $VENV_PYTHON ≠ cible $TARGET_PYTHON — recréation"
    rm -rf dbt-venv
  fi
fi

if [ ! -d dbt-venv ]; then
  $PYTHON_BIN -m venv dbt-venv
  ok "venv dbt créé (via $PYTHON_BIN)"
fi

source "$DBT_DIR/dbt-venv/bin/activate"
pip install --upgrade pip -q
pip install dbt-trino -q
ok "dbt-trino installé → $(dbt --version 2>&1 | head -1)"

# Initialiser le projet dbt s'il n'existe pas
if [ ! -d "$DBT_PROJECT" ]; then
  dbt init lakehouse_project --skip-profile-setup
  ok "Projet dbt initialisé"
fi

# Supprimer les modèles d'exemple générés par dbt init
rm -rf "$DBT_PROJECT/models/example"

# Copier les modèles depuis le repo (staging + marts)
# Le repo contient les modèles dans dbt/models/
DBT_REPO_DIR="${PROJECT_DIR}/dbt"
if [ -d "$DBT_REPO_DIR/models" ]; then
  cp -r "$DBT_REPO_DIR/models/staging" "$DBT_PROJECT/models/" 2>/dev/null || true
  cp -r "$DBT_REPO_DIR/models/marts"   "$DBT_PROJECT/models/" 2>/dev/null || true
  ok "Modèles dbt copiés depuis le repo"
fi

# Copier dbt_project.yml depuis le repo si présent
if [ -f "$DBT_REPO_DIR/dbt_project.yml" ]; then
  cp "$DBT_REPO_DIR/dbt_project.yml" "$DBT_PROJECT/dbt_project.yml"
  ok "dbt_project.yml copié depuis le repo"
else
  # Générer dbt_project.yml par défaut
  cat > "$DBT_PROJECT/dbt_project.yml" << 'EOF'
name: 'lakehouse_project'
version: '1.0.0'
config-version: 2

profile: 'lakehouse_project'

model-paths: ["models"]
test-paths: ["tests"]
macro-paths: ["macros"]
target-path: "target"
clean-targets: ["target", "dbt_packages"]

flags:
  require_certificate_validation: false

models:
  lakehouse_project:
    staging:
      +materialized: view
    marts:
      +materialized: table
EOF
  ok "dbt_project.yml généré"
fi

# Déployer profiles.yml
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

# ---------- 6b. Venv pipeline Python ----------------------------------------
PIPELINE_DIR="${PROJECT_DIR}/Provisions-Files/project/python/MinIO"
if [ -d "$PIPELINE_DIR" ]; then
  log "=== [6b] Venv pipeline Python ==="
  cd "$PIPELINE_DIR"

  if [ -d venv ]; then
    VENV_MINOR=$(venv/bin/python3 -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "99")
    if [ "$VENV_MINOR" -ge 13 ]; then
      log "  venv pipeline Python 3.${VENV_MINOR} → recréation avec python3.12"
      rm -rf venv
    fi
  fi

  if [ ! -d venv ]; then
    $PYTHON_BIN -m venv venv
    ok "venv pipeline créé"
  fi

  source venv/bin/activate
  pip install --upgrade pip -q
  pip install -r requirements.txt -q
  ok "Dépendances pipeline installées"
  deactivate
  cd "$PROJECT_DIR"
fi

# ---------- 7. Démarrage de la stack ----------------------------------------
log "=== [7/9] Démarrage de la stack Docker Compose ==="
cd "$SERVICE_DIR"
sg docker -c "docker compose -f $COMPOSE_FILE up -d --build"
ok "Stack démarrée"

# Health-check Trino (max 120s)
log "  Attente Trino prêt..."
TRINO_UP=0
for i in $(seq 1 24); do
  if curl -sf http://localhost:8080/v1/info | grep -q '"starting":false'; then
    TRINO_UP=1; break
  fi
  sleep 5
done
[ "$TRINO_UP" -eq 0 ] && log "  ⚠ Trino pas prêt après 120s — vérifier : docker compose logs trino"

# ---------- 8. Pipeline de données ------------------------------------------
log "=== [8/9] Chargement des données initiales ==="
if [ "$SKIP_DATA" = "--skip-data" ]; then
  log "  → Ignoré (--skip-data)"
else
  if [ -f "$PIPELINE_DIR/pipeline.py" ]; then
    cd "$PIPELINE_DIR"
    source venv/bin/activate
    log "  Exécution pipeline.py..."
    python3 pipeline.py
    ok "Pipeline exécuté"
    deactivate
    cd "$PROJECT_DIR"
  else
    log "  ⚠ pipeline.py introuvable"
  fi
fi

# ---------- 9. dbt run + dbt test -------------------------------------------
log "=== [9/9] dbt run + dbt test ==="
if [ "$SKIP_DATA" = "--skip-data" ]; then
  log "  → Ignoré (--skip-data)"
else
  source "$DBT_DIR/dbt-venv/bin/activate"
  cd "$DBT_PROJECT"

  # Vérifier que des modèles existent
  MODEL_COUNT=$(find models -name "*.sql" 2>/dev/null | wc -l)
  if [ "$MODEL_COUNT" -gt 0 ]; then
    log "  dbt run ($MODEL_COUNT modèles)..."
    dbt run  && ok "dbt run OK"
    dbt test && ok "dbt test OK"
  else
    log "  ⚠ Aucun modèle SQL trouvé dans $DBT_PROJECT/models — skip dbt"
  fi
  deactivate
fi

# ---------- Statut containers -----------------------------------------------
sg docker -c "docker compose -f $COMPOSE_FILE ps"

# ---------- Résumé ----------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=============================================="
echo " data-stack prêt !"
echo "=============================================="
echo " MinIO   : http://${IP}:9001  (admin / voir hive-site.xml)"
echo " Trino   : http://${IP}:8080"
echo ""
echo " Pipeline données :"
echo "   cd ${PIPELINE_DIR}"
echo "   source venv/bin/activate && python3 pipeline.py"
echo ""
echo " dbt :"
echo "   cd ${DBT_PROJECT}"
echo "   source ${DBT_DIR}/dbt-venv/bin/activate"
echo "   dbt run && dbt test"
echo "=============================================="