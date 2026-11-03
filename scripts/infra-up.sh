#!/usr/bin/env bash
# =============================================================================
# infra-up.sh — Despliega TODA la demo con un solo comando.
#
#   1. terraform init + apply (VPC, ALB, ASG, S3, CloudFront...)
#   2. Compila y sube el frontend (deploy-frontend.sh)
#   3. Espera a que las instancias estén "healthy" en el target group
#
# Uso:
#   cp infra/terraform.tfvars.example infra/terraform.tfvars   # y edítalo
#   bash scripts/infra-up.sh
#
# AUTO_APPROVE=1 evita la pregunta de confirmación de Terraform.
# Tiempo total aproximado: 10-15 minutos (CloudFront es lo más lento).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tf-outputs.sh
source "$SCRIPT_DIR/tf-outputs.sh"

log() { echo "[infra-up] $*"; }

for tool in terraform aws; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: falta '$tool'." >&2; exit 1; }
done

if [[ ! -f "$INFRA_DIR/terraform.tfvars" ]]; then
  echo "ERROR: falta infra/terraform.tfvars. Créalo a partir del ejemplo:" >&2
  echo "  cp infra/terraform.tfvars.example infra/terraform.tfvars" >&2
  exit 1
fi

# ---------- 1. Infraestructura ----------
log "terraform init..."
terraform -chdir="$INFRA_DIR" init -input=false

log "terraform apply..."
APPLY_ARGS=(-input=false)
[[ "${AUTO_APPROVE:-0}" == "1" ]] && APPLY_ARGS+=(-auto-approve)
terraform -chdir="$INFRA_DIR" apply "${APPLY_ARGS[@]}"

use_tf_profile
export AWS_REGION
AWS_REGION="$(tf_output region)"

# ---------- 2. Frontend ----------
log "Publicando el frontend..."
bash "$SCRIPT_DIR/deploy-frontend.sh"

# ---------- 3. Esperar instancias sanas ----------
TG_ARN="$(tf_output target_group_arn)"
log "Esperando a que las instancias pasen el health check (puede tardar ~5 min)..."
healthy=0
for _ in $(seq 1 60); do
  healthy="$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)"
  echo "  instancias healthy: $healthy"
  [[ "$healthy" -ge 2 ]] && break
  sleep 15
done

echo
log "================================================================"
log " URL de la demo:   $(tf_output cloudfront_url)"
log " Comprobar:        bash scripts/demo-check.sh"
log " Destruir todo:    bash scripts/infra-destroy.sh"
log "================================================================"
if [[ "$healthy" -lt 2 ]]; then
  log "AVISO: aún no hay 2 instancias healthy. Revisa el target group y"
  log "       /var/log/cloud-init-output.log en una instancia (Session Manager)."
fi
