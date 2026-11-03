#!/usr/bin/env bash
# =============================================================================
# infra-up.sh — Despliega TODA la demo con un solo comando.
#
#   1. Crea la base de red, IAM y target group para construir la AMI.
#   2. Construye la AMI desde backend/ local.
#   3. Aplica toda la infraestructura y publica el frontend.
#   4. Espera a que las instancias estén "healthy" en el target group.
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

APPLY_ARGS=(-input=false)
[[ "${AUTO_APPROVE:-0}" == "1" ]] && APPLY_ARGS+=(-auto-approve)

# Dos fases intencionales: la AMI requiere esta base, y el ASG requiere la AMI.
log "Preparando infraestructura para construir la AMI..."
terraform -chdir="$INFRA_DIR" apply "${APPLY_ARGS[@]}" \
  -target=aws_subnet.public -target=aws_route_table_association.public \
  -target=aws_security_group.app -target=aws_vpc_security_group_egress_rule.app_all \
  -target=aws_iam_instance_profile.ec2 \
  -target=aws_iam_role_policy_attachment.ssm -target=aws_iam_role_policy.demo_scaling \
  -target=aws_lb_target_group.api

log "Construyendo la AMI desde el backend local..."
bash "$SCRIPT_DIR/build-api-ami.sh"

log "Aplicando la infraestructura completa con la AMI preparada..."
terraform -chdir="$INFRA_DIR" apply "${APPLY_ARGS[@]}"

use_tf_profile
export AWS_REGION
AWS_REGION="$(tf_output region)"

# ---------- 2. Frontend ----------
log "Publicando el frontend..."
bash "$SCRIPT_DIR/deploy-frontend.sh"

# ---------- 3. Esperar instancias sanas ----------
ASG_NAME="$(tf_output asg_name)"
for _ in $(seq 1 120); do
  refresh="$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG_NAME" \
    --query 'InstanceRefreshes[0].Status' --output text)"
  case "$refresh" in
    None|Successful) break ;;
    Failed|Cancelled|RollbackFailed|RollbackSuccessful)
      echo "La renovación no terminó correctamente: $refresh" >&2; exit 1 ;;
  esac
  log "Renovando instancias con la AMI nueva: $refresh"
  sleep 10
done
case "$refresh" in None|Successful) ;; *) echo 'La renovación sigue pendiente.' >&2; exit 1;; esac
TG_ARN="$(tf_output target_group_arn)"
log "Esperando a que las instancias pasen el health check..."
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
