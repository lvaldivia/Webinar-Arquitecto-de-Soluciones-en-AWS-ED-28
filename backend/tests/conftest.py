"""Fixtures compartidas: IMDS simulado y un controlador de estrés falso."""

import pytest
from fastapi.testclient import TestClient

from app import metadata, stress
from app.main import app

FAKE_METADATA = {
    "instance_id": "i-0123456789abcdef0",
    "availability_zone": "us-east-1a",
    "region": "us-east-1",
    "source": "imds",
}


class FakeStressController(stress.StressController):
    """Igual al real, pero sin lanzar procesos (los tests no deben quemar CPU)."""

    def __init__(self) -> None:
        super().__init__()
        self.runs: list[int] = []

    def start(self, seconds: int) -> bool:
        accepted = super().start(seconds)
        if accepted:
            self.runs.append(seconds)
        return accepted

    def _run(self, seconds: int, cancelled) -> None:
        cancelled.wait()


@pytest.fixture
def fake_stress(monkeypatch) -> FakeStressController:
    controller = FakeStressController()
    monkeypatch.setattr(stress, "controller", controller)
    return controller


@pytest.fixture
def client(monkeypatch, fake_stress):
    # Simulamos IMDS: el lifespan de la app llamará a esta función al arrancar.
    monkeypatch.setattr(metadata, "fetch_from_imds", lambda: dict(FAKE_METADATA))
    metadata.reset_cache()
    with TestClient(app) as test_client:
        yield test_client
    metadata.reset_cache()
