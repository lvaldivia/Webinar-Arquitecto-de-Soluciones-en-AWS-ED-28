"""Configuración de la API, leída desde variables de entorno.

Todo lo configurable vive aquí para que sea fácil de encontrar en clase.
Los valores por defecto están documentados en .env.example.
"""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_version: str
    stress_max_seconds: int
    log_level: str


def load_settings() -> Settings:
    return Settings(
        app_version=os.getenv("APP_VERSION", "1.0.0"),
        stress_max_seconds=int(os.getenv("STRESS_MAX_SECONDS", "300")),
        log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
    )


settings = load_settings()
