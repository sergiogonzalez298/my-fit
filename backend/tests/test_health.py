import os

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import app, get_settings

TEST_SETTINGS = Settings(email="t@example.com", password="pw", region="EU", api_key="secret")


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr("app.main.check_speediance", lambda settings: None)
    app.dependency_overrides[get_settings] = lambda: TEST_SETTINGS
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_health_ok(client):
    response = client.get("/health", headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "speediance": "connected"}


def test_health_speediance_error(client, monkeypatch):
    def boom(settings):
        raise RuntimeError("login failed")

    monkeypatch.setattr("app.main.check_speediance", boom)
    response = client.get("/health", headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "speediance": "error"}


def test_health_rejects_wrong_api_key(client):
    response = client.get("/health", headers={"X-API-Key": "wrong"})
    assert response.status_code == 401


def test_health_rejects_missing_api_key(client):
    response = client.get("/health")
    assert response.status_code == 401
