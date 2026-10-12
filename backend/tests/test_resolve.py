import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import app, get_settings
from app import resolve as resolve_module

TEST_SETTINGS = Settings(email="t@example.com", password="pw", region="EU", api_key="secret")

BODY = {"names": ["Barbell Bench Press", "Encogimiento Quantum 3000"]}


class FakeGroup:
    def __init__(self, id, title):
        self.id = id
        self.title = title


class FakeClient:
    def __init__(self):
        self._groups = [FakeGroup(116, "Barbell Bench Press")]
        self._details = {
            116: {"isLeftRight": 0, "isBarbell": 1, "img": "https://img.example/group.jpg",
                  "actionLibraryList": [{"id": 424195710320641, "isDisplay": 1,
                                         "img": "https://img.example/variant.jpg"}]},
        }

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def login(self):
        pass

    def exercise_groups(self):
        return self._groups

    def exercise_group(self, group_id):
        return self._details[group_id]


@pytest.fixture
def client(monkeypatch, tmp_path):
    monkeypatch.setattr(resolve_module, "_cache_path", lambda: tmp_path / "ex.json")
    monkeypatch.setattr(resolve_module, "_make_client", lambda settings: FakeClient())
    app.dependency_overrides[get_settings] = lambda: TEST_SETTINGS
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_resolve_returns_title_and_variant_image(client):
    response = client.post("/speediance/resolve-exercises", json=BODY,
                           headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    exercises = response.json()["exercises"]
    bench = exercises[0]
    assert bench == {"name": "Barbell Bench Press", "resolved": True,
                     "title": "Barbell Bench Press",
                     "image": "https://img.example/variant.jpg"}
    unknown = exercises[1]
    assert unknown == {"name": "Encogimiento Quantum 3000", "resolved": False,
                       "title": None, "image": None}


def test_resolve_requires_api_key(client):
    response = client.post("/speediance/resolve-exercises", json=BODY)
    assert response.status_code == 401


def test_resolve_rejects_empty_names(client):
    response = client.post("/speediance/resolve-exercises", json={"names": []},
                           headers={"X-API-Key": "secret"})
    assert response.status_code == 422
