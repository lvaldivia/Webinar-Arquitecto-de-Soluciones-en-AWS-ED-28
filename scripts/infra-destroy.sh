#!/usr/bin/env bash
# =============================================================================
# infra-destroy.sh — Borra TODA la infraestructura de la demo.
#
# El bucket se vacía solo (force_destroy = true en Terraform).
# CloudFront tarda varios minutos en deshabilitarse y borrarse: es normal.
#
# Uso:
#   bash scripts/infra-destroy.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tf-outputs.sh
source "$SCRIPT_DIR/tf-outputs.sh"

command -v terraform >/dev/null 2>&1 || { echo "ERROR: falta terraform." >&2; exit 1; }

url="$(tf_output cloudfront_url)"
echo "Se va a DESTRUIR toda la infraestructura de la demo${url:+ ($url)}."
echo "Esto borra instancias, ALB, CloudFront, el bucket y su contenido. No se puede deshacer."
read -r -p "Escribe 'destruir' para confirmar: " answer

if [[ "$answer" != "destruir" ]]; then
  echo "Cancelado."
  exit 1
fi

terraform -chdir="$INFRA_DIR" destroy -input=false -auto-approve

echo
echo "[infra-destroy] Listo. Revisa en Billing → Bills que no quede nada cobrando."
