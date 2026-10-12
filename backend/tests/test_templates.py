import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import app, get_settings
from app import templates as templates_module

TEST_SETTINGS = Settings(email="t@example.com", password="pw", region="EU", api_key="secret")

BODY = {
    "name": "Empuje semana 42",
    "movements": [
        {"exerciseName": "Barbell Bench Press",
         "sets": [{"reps": 10, "weightKg": 45.0, "restSeconds": 90}]},
        {"exerciseName": "Dual-Handle Zottman Curl",
         "sets": [{"reps": 12, "weightKg": 9.0}]},
    ],
}


class FakeTemplate:
    def __init__(self, name, code="abc123", action_count=2):
        self.name = name
        self.code = code
        self.action_count = action_count


class FakeClient:
    """Duck-type del SpeedianceClient con escritura."""
    def __init__(self, existing=(), create_error=None):
        self._existing = list(existing)
        self._create_error = create_error
        self.created_payloads = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def login(self):
        pass

    def exercise_groups(self):
        from tests.test_catalog import FakeGroup
        return [FakeGroup(116, "Barbell Bench Press"),
                FakeGroup(200, "Dual-Handle Zottman Curl")]

    def exercise_group(self, group_id):
        details = {
            116: {"isLeftRight": 0, "isBarbell": 1,
                  "actionLibraryList": [{"id": 424195710320641, "isDisplay": 1}]},
            200: {"isLeftRight": 1, "isBarbell": 0,
                  "actionLibraryList": [{"id": 999001, "isDisplay": 1}]},
        }
        return details[group_id]

    def list_templates(self):
        return self._existing

    def create_template(self, name, movements):
        self.created_payloads.append((name, movements))
        if self._create_error:
            raise self._create_error
        return "newcode123"


@pytest.fixture
def client(monkeypatch, tmp_path):
    fake = FakeClient()
    monkeypatch.setattr(templates_module, "_cache_path", lambda: tmp_path / "ex.json")
    monkeypatch.setattr(templates_module, "_make_write_client",
                        lambda settings: fake)
    app.dependency_overrides[get_settings] = lambda: TEST_SETTINGS
    yield TestClient(app), fake
    app.dependency_overrides.clear()


def test_creates_template(client):
    http, fake = client
    response = http.post("/speediance/templates", json=BODY,
                         headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    body = response.json()
    assert body == {"code": "newcode123", "name": "Empuje semana 42",
                    "movementCount": 2, "deduplicated": False}
    # La librería recibe action_library_id + is_left_right + sets con peso por mango
    _, movements = fake.created_payloads[0]
    assert movements[0]["action_library_id"] == 424195710320641
    assert movements[0]["sets"] == [{"reps": 10, "weight": 45.0, "rest_seconds": 90}]
    assert movements[1]["is_left_right"] is True
    assert movements[1]["sets"] == [{"reps": 12, "weight": 9.0, "rest_seconds": 60}]


def test_unmatched_exercise_returns_422_and_creates_nothing(client):
    http, fake = client
    body = {**BODY, "movements": [BODY["movements"][0],
                                  {"exerciseName": "Encogimiento Quantum 3000",
                                   "sets": [{"reps": 10, "weightKg": 10.0}]}]}
    response = http.post("/speediance/templates", json=body,
                         headers={"X-API-Key": "secret"})
    assert response.status_code == 422
    assert response.json()["detail"]["unmatched"] == ["Encogimiento Quantum 3000"]
    assert fake.created_payloads == []


def test_duplicate_name_is_idempotent(client, monkeypatch, tmp_path):
    http, _ = client
    existing = FakeTemplate(name="empuje semana 42 ", code="existing9")
    fake2 = FakeClient(existing=[existing])
    monkeypatch.setattr(templates_module, "_make_write_client", lambda settings: fake2)
    response = http.post("/speediance/templates", json=BODY,
                         headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    body = response.json()
    assert body["code"] == "existing9"
    assert body["deduplicated"] is True
    assert fake2.created_payloads == []


def test_code10_quirk_confirms_by_listing(client, monkeypatch):
    from speediance.errors import SpeedianceAPIError
    http, _ = client
    fake3 = FakeClient(
        existing=[FakeTemplate(name="Empuje semana 42", code="quirky1")],
        create_error=SpeedianceAPIError(10, "Parameter error."),
    )
    monkeypatch.setattr(templates_module, "_make_write_client", lambda settings: fake3)
    response = http.post("/speediance/templates", json=BODY,
                         headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    assert response.json()["code"] == "quirky1"


def test_other_api_error_is_502(client, monkeypatch):
    from speediance.errors import SpeedianceAPIError
    http, _ = client
    fake4 = FakeClient(create_error=SpeedianceAPIError(99, "boom"))
    monkeypatch.setattr(templates_module, "_make_write_client", lambda settings: fake4)
    response = http.post("/speediance/templates", json=BODY,
                         headers={"X-API-Key": "secret"})
    assert response.status_code == 502


def test_requires_api_key(client):
    http, _ = client
    response = http.post("/speediance/templates", json=BODY)
    assert response.status_code == 401
