"""API de la demo: corre en un contenedor dentro de cada EC2, detrás del ALB.

Rutas:
  GET  /health          -> health check del ALB (liviano, sin dependencias)
  GET  /api/health      -> lo mismo, pero accesible vía CloudFront (/api/*)
  GET  /api/info        -> qué instancia y AZ respondió (y su % de CPU)
  POST /api/spell       -> genera un hechizo aleatorio
  POST /api/stress      -> sube la CPU para disparar el Auto Scaling
  GET  /api/grimoires   -> lista estática de grimorios de ejemplo
"""

import logging
import socket
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from app import cpu, metadata, spells, stress
from app.config import settings
from app.logging_config import setup_logging

setup_logging(settings.log_level)
logger = logging.getLogger("app")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # Consultamos IMDS una sola vez al arrancar y lo dejamos en memoria.
    metadata.load_metadata()
    # Medición de CPU en segundo plano (para verla en vivo en el panel A).
    cpu.monitor.start()
    yield


app = FastAPI(title="Grimorio API", version=settings.app_version, lifespan=lifespan)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def caster() -> dict:
    """Quién respondió: útil para ver el reparto del ALB en cada respuesta."""
    meta = metadata.get_metadata()
    return {"instance_id": meta["instance_id"], "availability_zone": meta["availability_zone"]}


@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = round((time.perf_counter() - start) * 1000, 2)

    # El ALB llama a /health cada pocos segundos: lo dejamos en DEBUG para no llenar los logs.
    level = logging.DEBUG if request.url.path == "/health" else logging.INFO
    logger.log(
        level,
        "request",
        extra={
            "fields": {
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": duration_ms,
                **caster(),
            }
        },
    )
    return response


# ---------- Health checks ----------

@app.get("/health")
def health() -> dict:
    # A propósito NO consulta nada externo: si una dependencia fallara, el ALB
    # marcaría unhealthy a TODAS las instancias a la vez.
    return {"status": "ok"}


@app.get("/api/health")
def api_health() -> dict:
    return {"status": "ok"}


# ---------- Info de la instancia ----------

@app.get("/api/info")
def info() -> dict:
    meta = metadata.get_metadata()
    return {
        "instance_id": meta["instance_id"],
        "availability_zone": meta["availability_zone"],
        "region": meta["region"],
        "hostname": socket.gethostname(),
        "version": settings.app_version,
        "timestamp": now_iso(),
        # Carga actual de la instancia: deja ver el "modo estrés" en segundos,
        # mucho antes de que el Auto Scaling reaccione.
        "cpu_percent": cpu.monitor.percent,
        "stress_remaining_seconds": stress.controller.remaining_seconds(),
    }


# ---------- Hechizos ----------

@app.post("/api/spell")
def cast_spell() -> dict:
    return {**spells.generate_spell(), "caster": caster(), "timestamp": now_iso()}


@app.get("/api/grimoires")
def list_grimoires() -> dict:
    return {"grimoires": spells.GRIMOIRES, "served_by": caster()}


# ---------- Estrés de CPU ----------

class StressRequest(BaseModel):
    seconds: int = Field(default=60, ge=1, description="Duración del estrés en segundos")


@app.post("/api/stress", status_code=202)
def start_stress(body: StressRequest) -> JSONResponse:
    # Si piden más que el máximo, lo recortamos en vez de rechazar.
    seconds = min(body.seconds, settings.stress_max_seconds)

    if not stress.controller.start(seconds):
        return JSONResponse(
            status_code=409,
            content={
                "status": "busy",
                "message": "Ya hay un estrés en curso en esta instancia",
                "remaining_seconds": stress.controller.remaining_seconds(),
                **caster(),
            },
        )

    return JSONResponse(
        status_code=202,
        content={
            "status": "accepted",
            "seconds": seconds,
            "max_seconds": settings.stress_max_seconds,
            **caster(),
        },
    )
