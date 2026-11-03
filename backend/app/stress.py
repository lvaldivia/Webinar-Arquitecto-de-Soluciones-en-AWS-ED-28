"""Generador de carga de CPU para demostrar el escalado del Auto Scaling Group.

- Usa procesos (multiprocessing) y no hilos: por el GIL de Python, varios
  hilos no logran ocupar varios núcleos; varios procesos sí.
- Lanza un proceso por núcleo para llevar la CPU de la instancia cerca del 100 %.
- Corre en segundo plano: el endpoint responde 202 al instante y la API
  sigue atendiendo peticiones (y health checks) mientras tanto.
- Solo se permite un estrés a la vez por instancia.
"""

import logging
import math
import multiprocessing
import os
import threading
import time

logger = logging.getLogger(__name__)


def burn_cpu(seconds: float) -> None:
    """Hace cálculos inútiles hasta que pasan `seconds` segundos."""
    deadline = time.monotonic() + seconds
    value = 0
    while time.monotonic() < deadline:
        value = (value * 31 + 7) % 1_000_003


class StressController:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._active_until = 0.0

    def remaining_seconds(self) -> int:
        return max(0, math.ceil(self._active_until - time.monotonic()))

    def is_active(self) -> bool:
        return self.remaining_seconds() > 0

    def start(self, seconds: int) -> bool:
        """Inicia el estrés. Devuelve False si ya hay uno en curso."""
        with self._lock:
            if self.is_active():
                return False
            self._active_until = time.monotonic() + seconds

        thread = threading.Thread(target=self._run, args=(seconds,), daemon=True)
        thread.start()
        return True

    def _run(self, seconds: int) -> None:
        cpus = os.cpu_count() or 1
        logger.info("estrés iniciado", extra={"fields": {"seconds": seconds, "cpus": cpus}})

        # "spawn" crea procesos limpios; es seguro aunque el servidor tenga hilos.
        context = multiprocessing.get_context("spawn")
        processes = [
            context.Process(target=burn_cpu, args=(seconds,), daemon=True) for _ in range(cpus)
        ]
        for process in processes:
            process.start()
        for process in processes:
            process.join()

        logger.info("estrés terminado", extra={"fields": {"seconds": seconds}})


# Una sola instancia por proceso de la API.
controller = StressController()
