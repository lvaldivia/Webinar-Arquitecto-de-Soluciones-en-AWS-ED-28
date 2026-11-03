"""Tests de todos los endpoints de la API."""

from app import spells
from app.config import settings
from tests.conftest import FAKE_METADATA


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_api_health(client):
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_info_returns_instance_metadata(client):
    response = client.get("/api/info")
    assert response.status_code == 200
    body = response.json()
    assert body["instance_id"] == FAKE_METADATA["instance_id"]
    assert body["availability_zone"] == FAKE_METADATA["availability_zone"]
    assert body["region"] == FAKE_METADATA["region"]
    assert body["version"] == settings.app_version
    assert body["hostname"]
    assert body["timestamp"]
    assert "cpu_percent" in body
    assert body["stress_remaining_seconds"] == 0


def test_info_reports_active_stress(client):
    client.post("/api/stress", json={"seconds": 60})
    assert client.get("/api/info").json()["stress_remaining_seconds"] > 0


def test_spell_has_valid_fields(client):
    response = client.post("/api/spell")
    assert response.status_code == 200
    body = response.json()
    assert body["element"] in spells.ELEMENTS
    assert 1 <= body["power"] <= 100
    assert body["name"]
    assert body["caster"] == {
        "instance_id": FAKE_METADATA["instance_id"],
        "availability_zone": FAKE_METADATA["availability_zone"],
    }


def test_grimoires_list(client):
    response = client.get("/api/grimoires")
    assert response.status_code == 200
    grimoires = response.json()["grimoires"]
    assert len(grimoires) > 0
    for grimoire in grimoires:
        assert {"id", "name", "leaves", "element", "pages", "description"} <= grimoire.keys()


def test_stress_is_accepted_with_202(client, fake_stress):
    response = client.post("/api/stress", json={"seconds": 30})
    assert response.status_code == 202
    body = response.json()
    assert body["status"] == "accepted"
    assert body["seconds"] == 30
    assert body["instance_id"] == FAKE_METADATA["instance_id"]
    assert fake_stress.runs == [30]


def test_stress_is_capped_to_max_seconds(client, fake_stress):
    response = client.post("/api/stress", json={"seconds": 99_999})
    assert response.status_code == 202
    assert response.json()["seconds"] == settings.stress_max_seconds


def test_stress_rejects_second_request_while_active(client):
    assert client.post("/api/stress", json={"seconds": 60}).status_code == 202
    response = client.post("/api/stress", json={"seconds": 60})
    assert response.status_code == 409
    assert response.json()["status"] == "busy"
    assert response.json()["remaining_seconds"] > 0


def test_stress_rejects_invalid_seconds(client):
    assert client.post("/api/stress", json={"seconds": 0}).status_code == 422
    assert client.post("/api/stress", json={"seconds": "mucho"}).status_code == 422


def test_stop_stress_is_idempotent_and_allows_restart(client):
    assert client.post("/api/stress", json={"seconds": 300}).status_code == 202
    response = client.post("/api/stress/stop")
    assert response.status_code == 200
    assert response.json()["status"] == "stopped"
    assert response.json()["instance_id"] == FAKE_METADATA["instance_id"]
    assert client.get("/api/info").json()["stress_remaining_seconds"] == 0
    assert client.post("/api/stress/stop").json()["status"] == "stopped"
    assert client.post("/api/stress", json={"seconds": 30}).status_code == 202
