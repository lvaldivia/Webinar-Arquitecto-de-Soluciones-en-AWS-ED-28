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


def burn_cpu(seconds: float, cancelled=None) -> None:
    """Hace cálculos inútiles hasta que pasan `seconds` segundos."""
    deadline = time.monotonic() + seconds
    value = 0
    while time.monotonic() < deadline:
        if cancelled is not None and cancelled.is_set():
            break
        value = (value * 31 + 7) % 1_000_003


class StressController:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._active_until = 0.0
        self._thread: threading.Thread | None = None
        self._cancelled = None

    def remaining_seconds(self) -> int:
        return max(0, math.ceil(self._active_until - time.monotonic()))

    def is_active(self) -> bool:
        return self.remaining_seconds() > 0

    def start(self, seconds: int) -> bool:
        """Inicia el estrés. Devuelve False si ya hay uno en curso."""
        with self._lock:
            if self.is_active() or (self._thread is not None and self._thread.is_alive()):
                return False
            self._active_until = time.monotonic() + seconds
            cancelled = multiprocessing.get_context("spawn").Event()
            self._cancelled = cancelled
            self._thread = threading.Thread(target=self._execute, args=(seconds, cancelled), daemon=True)
            self._thread.start()

        return True

    def stop(self) -> bool:
        """Cancela también un trabajo que todavía está creando sus procesos."""
        with self._lock:
            if self._cancelled is not None:
                self._cancelled.set()
            self._active_until = 0.0
            thread = self._thread
        if thread is not None:
            thread.join(timeout=2)
        return thread is None or not thread.is_alive()

    def _execute(self, seconds: int, cancelled) -> None:
        try:
            self._run(seconds, cancelled)
        finally:
            with self._lock:
                if self._cancelled is cancelled:
                    self._active_until = 0.0

    def _run(self, seconds: int, cancelled) -> None:
        cpus = os.cpu_count() or 1
        logger.info("estrés iniciado", extra={"fields": {"seconds": seconds, "cpus": cpus}})

        # "spawn" crea procesos limpios; es seguro aunque el servidor tenga hilos.
        context = multiprocessing.get_context("spawn")
        processes = [
            context.Process(target=burn_cpu, args=(seconds, cancelled), daemon=True) for _ in range(cpus)
        ]
        started = []
        try:
            for process in processes:
                if cancelled.is_set():
                    break
                process.start()
                started.append(process)
            for process in started:
                process.join()
        finally:
            cancelled.set()
            for process in started:
                process.join(timeout=0.5)
                if process.is_alive():
                    process.terminate()
                    process.join()

        logger.info("estrés terminado", extra={"fields": {"seconds": seconds}})


# Una sola instancia por proceso de la API.
controller = StressController()
