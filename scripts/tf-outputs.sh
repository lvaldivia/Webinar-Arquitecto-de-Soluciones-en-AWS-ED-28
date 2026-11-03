#!/usr/bin/env bash
# =============================================================================
# tf-outputs.sh — Funciones compartidas para leer los outputs de Terraform.
# No se ejecuta solo: lo cargan otros scripts con `source`.
# =============================================================================

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../infra" && pwd)"

# Devuelve un output de Terraform, o vacío si no hay infraestructura desplegada.
tf_output() {
  command -v terraform >/dev/null 2>&1 || return 0
  terraform -chdir="$INFRA_DIR" output -raw "$1" 2>/dev/null || true
}

# Usa el mismo perfil de AWS que Terraform (salvo que ya hayas definido AWS_PROFILE).
use_tf_profile() {
  local profile
  profile="$(tf_output aws_profile)"
  if [[ -n "$profile" && -z "${AWS_PROFILE:-}" ]]; then
    export AWS_PROFILE="$profile"
  fi
}
