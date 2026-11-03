#!/bin/bash
# =============================================================================
# user-data.sh — Pégalo en el launch template:
#   EC2 → Launch templates → Advanced details → User data
#
# Se ejecuta UNA vez, como root, cuando arranca cada instancia nueva del
# Auto Scaling Group. Así cualquier instancia (la inicial, la que reemplaza a
# una caída o la que se agrega al escalar) queda lista sin intervención.
#
# Para ver qué pasó dentro de la instancia:
#   sudo cat /var/log/cloud-init-output.log
#
# 👉 Cambia REPO_URL por la URL de TU repositorio (debe ser público).
# =============================================================================
set -euxo pipefail

REPO_URL="https://github.com/lvaldivia/Webinar-Arquitecto-de-Soluciones-en-AWS-ED-28.git"
BRANCH="main"

dnf install -y git
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" /opt/grimorios
bash /opt/grimorios/scripts/setup-instance.sh
