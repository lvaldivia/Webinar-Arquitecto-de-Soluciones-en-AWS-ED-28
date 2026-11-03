# Imagen de la API de la demo.
# Construir:  docker build -t grimorio-api ./backend
# Correr:     docker run -p 8080:8080 grimorio-api
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=1.0.0 \
    STRESS_MAX_SECONDS=300 \
    LOG_LEVEL=INFO

WORKDIR /app

# Usuario sin privilegios: si alguien compromete la app, no es root en el contenedor.
RUN useradd --create-home --uid 10001 appuser

# Primero solo las dependencias, para aprovechar la caché de capas de Docker.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

USER appuser

# 8080 (> 1024) permite escuchar sin ser root. El target group del ALB apunta a este puerto.
EXPOSE 8080

# Docker revisa la salud del contenedor con el mismo endpoint que usa el ALB.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)" || exit 1

# --no-access-log: los accesos ya se registran en JSON desde un middleware de la app.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
