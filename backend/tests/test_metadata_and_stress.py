"""Tests de IMDSv2 (simulado), del fallback local y del quemador de CPU."""

import time
import urllib.error

from app import metadata, stress


def test_imdsv2_requests_token_first_and_uses_it(monkeypatch):
    calls = []
    responses = {
        "api/token": "token-123",
        "meta-data/instance-id": "i-abc",
        "meta-data/placement/availability-zone": "us-east-1b",
        "meta-data/placement/region": "us-east-1",
    }

    def fake_request(url, method="GET", headers=None):
        calls.append((method, url, headers or {}))
        return responses[url.removeprefix(metadata.IMDS_BASE_URL + "/")]

    monkeypatch.setattr(metadata, "_request", fake_request)
    result = metadata.fetch_from_imds()

    assert result["instance_id"] == "i-abc"
    assert result["availability_zone"] == "us-east-1b"
    # Paso 1: PUT del token. Paso 2: GETs con el token en el header.
    assert calls[0][0] == "PUT"
    assert "X-aws-ec2-metadata-token-ttl-seconds" in calls[0][2]
    for method, _url, headers in calls[1:]:
        assert method == "GET"
        assert headers["X-aws-ec2-metadata-token"] == "token-123"


def test_falls_back_to_simulated_metadata_when_imds_fails(monkeypatch):
    def unreachable(*_args, **_kwargs):
        raise urllib.error.URLError("timed out")

    monkeypatch.setattr(metadata, "_request", unreachable)
    metadata.reset_cache()

    result = metadata.load_metadata()
    assert result["instance_id"].startswith("local-")
    assert result["availability_zone"] == "local-az"
    assert metadata.get_metadata() is result  # queda cacheado en memoria
    metadata.reset_cache()


def test_burn_cpu_stops_after_given_seconds():
    start = time.monotonic()
    stress.burn_cpu(0.1)
    assert 0.1 <= time.monotonic() - start < 1.0
