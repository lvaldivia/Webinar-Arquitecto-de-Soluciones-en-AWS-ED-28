#!/usr/bin/env bash
# =============================================================================
# setup-instance.sh — Prepara una EC2 (Amazon Linux 2023) y levanta la API.
#
# Qué hace:
#   1. Instala Docker y git (si faltan) y deja Docker activo al arrancar.
#   2. Clona el repo (si aún no está en la instancia).
#   3. Llama a deploy-api.sh: build de la imagen y contenedor en el puerto 8080.
#
# Uso (como root o con sudo):
#   - Desde el repo ya clonado:      sudo bash scripts/setup-instance.sh
#   - Sin el repo en la instancia:   sudo REPO_URL=https://github.com/usuario/repo.git bash setup-instance.sh
#   - Automático en cada instancia nueva del ASG: ver scripts/user-data.sh
#
# Es idempotente: se puede ejecutar varias veces sin romper nada.
# =============================================================================
set -euo pipefail

REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[setup] $*"; }

if [[ $EUID -ne 0 ]]; then
  log "Necesito permisos de root (instalar paquetes y usar Docker). Reintentando con sudo..."
  exec sudo --preserve-env=REPO_URL,BRANCH,REPO_DIR bash "$0" "$@"
fi

# Si el script corre desde un repo clonado, usamos ese repo; si no, /opt/grimorios.
if git -C "$SCRIPT_DIR/.." rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  REPO_DIR="${REPO_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
else
  REPO_DIR="${REPO_DIR:-/opt/grimorios}"
fi

# ---------- 1. Paquetes ----------
if ! command -v docker >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
  log "Instalando docker y git..."
  dnf install -y docker git
fi

log "Activando Docker (y que arranque solo si la instancia se reinicia)..."
systemctl enable --now docker

# ---------- 2. Código ----------
if [[ ! -d "$REPO_DIR/.git" ]]; then
  if [[ -z "$REPO_URL" ]]; then
    echo "ERROR: no encontré el repo en $REPO_DIR y no definiste REPO_URL." >&2
    exit 1
  fi
  log "Clonando $REPO_URL (rama $BRANCH) en $REPO_DIR..."
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

# ---------- 3. Despliegue de la API ----------
exec bash "$REPO_DIR/scripts/deploy-api.sh"
