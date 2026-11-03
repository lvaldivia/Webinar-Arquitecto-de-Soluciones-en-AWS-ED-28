#!/usr/bin/env bash
# =============================================================================
# demo-check.sh — Comprueba la arquitectura desde la terminal.
#
#   1. Llama 10 veces a /api/info y muestra qué instancia y AZ respondió.
#   2. Pide 2 veces un archivo estático y muestra el X-Cache (Miss → Hit).
#
# Uso:
#   bash scripts/demo-check.sh                            # con Terraform: usa el output cloudfront_url
#   bash scripts/demo-check.sh https://dxxxxxxxxxxxx.cloudfront.net
#   bash scripts/demo-check.sh http://localhost:8080      # contra docker compose
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tf-outputs.sh
source "$SCRIPT_DIR/tf-outputs.sh"

URL="${1:-${CLOUDFRONT_URL:-$(tf_output cloudfront_url)}}"
REQUESTS="${REQUESTS:-10}"

if [[ -z "$URL" ]]; then
  echo "Uso: bash scripts/demo-check.sh <url-de-cloudfront>" >&2
  exit 1
fi
# Sin esquema: https para CloudFront, http para pruebas locales.
if [[ "$URL" != http* ]]; then
  if [[ "$URL" == localhost* || "$URL" == 127.0.0.1* ]]; then URL="http://$URL"; else URL="https://$URL"; fi
fi
URL="${URL%/}"

# Extrae "campo":"valor" de un JSON plano sin depender de jq.
json_field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }

# Busca un encabezado (sin distinguir mayúsculas) en una respuesta de curl -i.
# (|| true: si el encabezado no existe, no es un error; p. ej. en local no hay X-Cache).
header_value() { tr -d '\r' | { grep -i "^$1:" || true; } | head -1 | cut -d' ' -f2-; }

echo "== Reparto de tráfico: $REQUESTS llamadas a $URL/api/info"
printf "%-4s %-6s %-22s %-14s %s\n" "#" "HTTP" "INSTANCIA" "AZ" "X-CACHE"

summary=""
for i in $(seq 1 "$REQUESTS"); do
  response="$(curl -s -i --max-time 5 "$URL/api/info" || true)"
  status="$(echo "$response" | head -1 | awk '{print $2}')"
  body="$(echo "$response" | tail -1)"
  instance="$(echo "$body" | json_field instance_id)"
  az="$(echo "$body" | json_field availability_zone)"
  x_cache="$(echo "$response" | header_value x-cache)"

  printf "%-4s %-6s %-22s %-14s %s\n" "$i" "${status:-ERR}" "${instance:--}" "${az:--}" "${x_cache:-(sin X-Cache)}"
  [[ -n "$instance" ]] && summary+="$instance ($az)"$'\n'
  sleep 0.5
done

echo
echo "== Respuestas por instancia"
if [[ -n "$summary" ]]; then
  printf "%s" "$summary" | sort | uniq -c
else
  echo "   Ninguna respuesta válida. Revisa el target group y el behavior /api/* de CloudFront."
fi

echo
echo "== Caché de CloudFront: $URL/assets/grimorio.json"
for attempt in 1 2; do
  # GET (como el navegador), no HEAD: un HEAD con Miss no guarda el objeto en la caché.
  x_cache="$(curl -s -D - -o /dev/null --max-time 5 "$URL/assets/grimorio.json" | header_value x-cache || true)"
  echo "   Intento $attempt: ${x_cache:-sin CloudFront (local)}"
  sleep 1
done
echo "   (Esperado en AWS: el primero 'Miss from cloudfront' si nadie lo pidió antes; luego 'Hit from cloudfront'.)"
