"""Mide el uso de CPU de la instancia, para mostrarlo en vivo en la demo.

Lee /proc/stat cada segundo (sin dependencias extra). Dentro de un contenedor,
/proc/stat refleja la CPU del HOST, es decir, de la instancia EC2: el mismo
valor que CloudWatch usa para el Auto Scaling.

En sistemas sin /proc/stat (Windows o Mac sin Docker) el valor queda en None.
"""

import threading
import time

PROC_STAT = "/proc/stat"


def read_cpu_times(path: str = PROC_STAT) -> tuple[int, int] | None:
    """Devuelve (tiempo_ocioso, tiempo_total) acumulados de todos los núcleos."""
    try:
        with open(path, encoding="utf-8") as file:
            first_line = file.readline()
    except OSError:
        return None

    parts = first_line.split()
    if not parts or parts[0] != "cpu":
        return None

    values = [int(value) for value in parts[1:]]
    # Columnas: user nice system idle iowait irq softirq steal ...
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return idle, sum(values)


def usage_percent(before: tuple[int, int], after: tuple[int, int]) -> float:
    """% de CPU ocupada entre dos lecturas."""
    idle_delta = after[0] - before[0]
    total_delta = after[1] - before[1]
    if total_delta <= 0:
        return 0.0
    return round(100 * (1 - idle_delta / total_delta), 1)


class CpuMonitor:
    def __init__(self, interval: float = 1.0) -> None:
        self.interval = interval
        self.percent: float | None = None
        self._started = False

    def start(self) -> None:
        if self._started:
            return
        self._started = True
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self) -> None:
        previous = read_cpu_times()
        if previous is None:
            return  # no hay /proc/stat: dejamos percent en None
        while True:
            time.sleep(self.interval)
            current = read_cpu_times()
            if current is not None:
                self.percent = usage_percent(previous, current)
                previous = current


monitor = CpuMonitor()
