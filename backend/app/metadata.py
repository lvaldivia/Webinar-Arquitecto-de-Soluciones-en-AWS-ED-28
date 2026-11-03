"""Metadata de la instancia EC2 usando IMDSv2.

IMDSv2 funciona en dos pasos:
  1. PUT  /latest/api/token  -> devuelve un token de sesión.
  2. GET  /latest/meta-data/... con el header X-aws-ec2-metadata-token.

Como la API corre dentro de un contenedor, la petición hace un "salto" extra
(contenedor -> host). Por eso en el launch template se configura
http_put_response_hop_limit = 2; con 1 el token nunca llega al contenedor
y caeríamos en los valores simulados.

En local no existe IMDS: si no responde en menos de 1 segundo usamos
valores simulados (local-xxxx / local-az).
"""

import hashlib
import logging
import socket
import urllib.error
import urllib.request

logger = logging.getLogger(__name__)

IMDS_BASE_URL = "http://169.254.169.254/latest"
TOKEN_TTL_SECONDS = "21600"
IMDS_TIMEOUT_SECONDS = 1.0

# IMDS es una IP local del host: nunca debe pasar por un proxy HTTP.
_opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

_cached_metadata: dict | None = None


def _request(url: str, method: str = "GET", headers: dict | None = None) -> str:
    request = urllib.request.Request(url, method=method, headers=headers or {})
    with _opener.open(request, timeout=IMDS_TIMEOUT_SECONDS) as response:
        return response.read().decode("utf-8").strip()


def fetch_from_imds() -> dict:
    """Consulta IMDSv2. Lanza una excepción si IMDS no está disponible."""
    token = _request(
        f"{IMDS_BASE_URL}/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": TOKEN_TTL_SECONDS},
    )
    auth_header = {"X-aws-ec2-metadata-token": token}

    def get(path: str) -> str:
        return _request(f"{IMDS_BASE_URL}/meta-data/{path}", headers=auth_header)

    return {
        "instance_id": get("instance-id"),
        "availability_zone": get("placement/availability-zone"),
        "region": get("placement/region"),
        "source": "imds",
    }


def simulated_metadata() -> dict:
    """Valores para desarrollo local.

    El sufijo sale del hostname del contenedor, así cada réplica de
    `docker compose up --scale api=3` tiene un instance_id distinto y estable.
    """
    suffix = hashlib.sha1(socket.gethostname().encode()).hexdigest()[:4]
    return {
        "instance_id": f"local-{suffix}",
        "availability_zone": "local-az",
        "region": "local",
        "source": "simulado",
    }


def load_metadata() -> dict:
    """Carga la metadata (IMDS o simulada) y la guarda en memoria."""
    global _cached_metadata
    try:
        _cached_metadata = fetch_from_imds()
        logger.info("metadata obtenida de IMDSv2", extra={"fields": _cached_metadata})
    except (urllib.error.URLError, OSError, ValueError) as error:
        _cached_metadata = simulated_metadata()
        logger.warning(
            "IMDS no disponible, usando metadata simulada",
            extra={"fields": {**_cached_metadata, "error": str(error)}},
        )
    return _cached_metadata


def get_metadata() -> dict:
    """Devuelve la metadata cacheada (la carga la primera vez)."""
    if _cached_metadata is None:
        return load_metadata()
    return _cached_metadata


def reset_cache() -> None:
    """Solo para tests."""
    global _cached_metadata
    _cached_metadata = None
