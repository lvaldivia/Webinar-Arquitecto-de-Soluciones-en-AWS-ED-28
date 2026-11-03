#!/usr/bin/env bash
# =============================================================================
# deploy-api.sh — Construye la imagen de la API y (re)inicia el contenedor.
#
# Se ejecuta EN la instancia EC2 (lo llama setup-instance.sh la primera vez).
# Para desplegar una versión nueva en una instancia ya configurada:
#   sudo bash /opt/grimorios/scripts/deploy-api.sh
#
# Variables opcionales:
#   SKIP_PULL=1     no hace git pull (despliega lo que ya está en disco)
#   APP_VERSION=x   versión que mostrará /api/info (por defecto: commit actual)
#
# Tip de la clase: en un ASG es mejor NO actualizar instancias "a mano".
# Lo recomendado es un "Instance refresh": el ASG reemplaza las instancias
# de a poco y cada una nueva ejecuta el user data con el código más reciente.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE="grimorio-api:latest"
CONTAINER="grimorio-api"
PORT=8080 # el target group del ALB apunta a este puerto

log() { echo "[deploy-api] $*"; }

if [[ $EUID -ne 0 ]]; then
  exec sudo --preserve-env=SKIP_PULL,APP_VERSION bash "$0" "$@"
fi

cd "$REPO_DIR"

# cloud-init ejecuta el user data SIN la variable HOME, y git/docker la necesitan.
export HOME="${HOME:-/root}"

# ---------- Código ----------
if [[ "${SKIP_PULL:-0}" != "1" ]]; then
  log "Actualizando código (git pull)..."
  # -c safe.directory: el repo puede pertenecer a otro usuario (lo clonó root
  # desde el user data). Se pasa solo para este comando, sin tocar la config global.
  git -c safe.directory="$REPO_DIR" pull --ff-only
fi

# ---------- Configuración ----------
# Si existe .env en la raíz del repo, se pasa al contenedor (ver .env.example).
ENV_FILE_ARGS=()
if [[ -f "$REPO_DIR/.env" ]]; then
  log "Usando variables de $REPO_DIR/.env"
  ENV_FILE_ARGS=(--env-file "$REPO_DIR/.env")
fi

# Versión que muestra /api/info. Prioridad:
#   1. APP_VERSION pasada al script   2. APP_VERSION del .env   3. el commit actual
VERSION_ARGS=()
if [[ -n "${APP_VERSION:-}" ]]; then
  VERSION_ARGS=(-e "APP_VERSION=$APP_VERSION")
elif ! grep -qs '^APP_VERSION=' "$REPO_DIR/.env"; then
  VERSION_ARGS=(-e "APP_VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo dev)")
fi

# ---------- Build ----------
log "Construyendo la imagen $IMAGE..."
docker build -t "$IMAGE" "$REPO_DIR/backend"

# ---------- Run ----------
log "Reemplazando el contenedor $CONTAINER..."
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d \
  --name "$CONTAINER" \
  --restart always \
  -p "$PORT:8080" \
  "${ENV_FILE_ARGS[@]}" \
  "${VERSION_ARGS[@]}" \
  --log-opt max-size=10m --log-opt max-file=3 \
  "$IMAGE" >/dev/null

# ---------- Verificación ----------
log "Esperando a que /health responda..."
for _ in $(seq 1 30); do
  if curl -fsS "http://localhost:$PORT/health" >/dev/null 2>&1; then
    INFO="$(curl -fsS "http://localhost:$PORT/api/info")"
    log "API arriba: $INFO"

    # Si la metadata es simulada dentro de EC2, casi siempre es el hop limit de IMDS.
    if [[ "$INFO" == *'"instance_id":"local-'* ]]; then
      log "AVISO: la API no pudo leer IMDS y usa valores simulados (local-xxxx)."
      log "       Revisa en el launch template: IMDSv2 'required' y 'Metadata response hop limit' = 2."
    fi
    log "Listo."
    exit 0
  fi
  sleep 2
done

echo "ERROR: la API no respondió en /health. Últimos logs:" >&2
docker logs --tail 50 "$CONTAINER" >&2
exit 1
