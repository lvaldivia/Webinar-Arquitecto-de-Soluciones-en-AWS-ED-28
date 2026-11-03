#!/usr/bin/env bash
# =============================================================================
# deploy-frontend.sh — Compila el frontend y lo publica en S3 (+ CloudFront).
#
# Uso:
#   bash scripts/deploy-frontend.sh                      # con Terraform: lee bucket y distribución de los outputs
#   bash scripts/deploy-frontend.sh <bucket> [distribution-id]
#   BUCKET=mi-bucket DISTRIBUTION_ID=E123ABC bash scripts/deploy-frontend.sh
#
# Funciona en tu laptop o en la EC2:
#   - Si hay Node >= 22 instalado, compila con npm.
#   - Si no, compila dentro de Docker (usa la etapa "build" del Dockerfile).
#
# Requisitos: AWS CLI v2 con credenciales que puedan escribir en el bucket
# (s3:ListBucket, s3:PutObject, s3:DeleteObject) y, si pasas la distribución,
# cloudfront:CreateInvalidation. En la EC2 eso lo da el rol de la instancia.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tf-outputs.sh
source "$SCRIPT_DIR/tf-outputs.sh"

# Prioridad: argumentos > variables de entorno > outputs de Terraform.
BUCKET="${1:-${BUCKET:-$(tf_output bucket_name)}}"
DISTRIBUTION_ID="${2:-${DISTRIBUTION_ID:-$(tf_output distribution_id)}}"
use_tf_profile
FRONTEND_DIR="$(cd "$SCRIPT_DIR/../frontend" && pwd)"
DIST_DIR="$FRONTEND_DIR/dist"

log() { echo "[deploy-frontend] $*"; }

if [[ -z "$BUCKET" ]]; then
  echo "No encontré el bucket (¿desplegaste con Terraform?)." >&2
  echo "Uso: bash scripts/deploy-frontend.sh <bucket> [distribution-id]" >&2
  exit 1
fi

# ---------- 0. Verificaciones ----------
command -v aws >/dev/null 2>&1 || { echo "ERROR: falta AWS CLI v2." >&2; exit 1; }
log "Cuenta de AWS en uso:"
aws sts get-caller-identity --query Arn --output text

# ---------- 1. Build ----------
node_major() { node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }

if command -v npm >/dev/null 2>&1 && [[ "$(node_major)" -ge 22 ]]; then
  log "Compilando con Node $(node --version)..."
  (cd "$FRONTEND_DIR" && npm ci && npm run build)
elif command -v docker >/dev/null 2>&1; then
  log "Node >= 22 no disponible: compilando dentro de Docker..."
  docker build --target build -t grimorio-web-build "$FRONTEND_DIR"
  # Creamos un contenedor (sin ejecutarlo) solo para copiar dist/ hacia afuera.
  container_id="$(docker create grimorio-web-build)"
  rm -rf "$DIST_DIR"
  docker cp "$container_id:/app/dist" "$DIST_DIR"
  docker rm "$container_id" >/dev/null
else
  echo "ERROR: necesito Node >= 22 o Docker para compilar el frontend." >&2
  exit 1
fi

[[ -f "$DIST_DIR/index.html" ]] || { echo "ERROR: el build no generó dist/index.html" >&2; exit 1; }

# ---------- 2. Subida a S3 ----------
# --delete borra del bucket lo que ya no existe en dist/ (builds viejos).
log "Sincronizando dist/ con s3://$BUCKET ..."
aws s3 sync "$DIST_DIR/" "s3://$BUCKET/" --delete

# index.html no lleva hash en el nombre: le pedimos al navegador que siempre
# revalide, para que vea enseguida el nuevo build. Los JS/CSS sí tienen hash.
aws s3 cp "$DIST_DIR/index.html" "s3://$BUCKET/index.html" \
  --cache-control "no-cache" --content-type "text/html; charset=utf-8"

# ---------- 3. Invalidación de CloudFront ----------
if [[ -n "$DISTRIBUTION_ID" ]]; then
  log "Invalidando la caché de CloudFront ($DISTRIBUTION_ID)..."
  invalidation_id="$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" --paths "/*" \
    --query Invalidation.Id --output text)"
  log "Invalidación $invalidation_id creada (tarda 1-2 minutos en completarse)."
else
  log "Sin DISTRIBUTION_ID: no invalido CloudFront. Los edges pueden servir la versión anterior hasta que expire su caché."
fi

log "Listo."
