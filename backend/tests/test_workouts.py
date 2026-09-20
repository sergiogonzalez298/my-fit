from datetime import date, datetime, timezone

import pytest
from fastapi.testclient import TestClient
from speediance.models import Exercise, TrainingSession, WorkSet

from app.config import Settings
from app.main import app, get_settings
from app.speediance_client import session_to_dict

TEST_SETTINGS = Settings(email="t@example.com", password="pw", region="EU", api_key="secret")


def make_session(exercises=None, finished_at=None):
    return TrainingSession(
        training_id=998877,
        day=date(2026, 9, 18),
        title="Push Day",
        finished_at=finished_at,
        duration_min=45,
        calories=320,
        volume=6820.0,
        type=1,
        exercises=exercises or [],
    )


def dual_handle_exercise():
    """3 series (8/10/12 reps), 25 kg por mango (load_points=2 → 50 kg total)."""
    sets = [
        WorkSet(reps=reps, target_reps=reps, weights=[25.0] * reps, seconds=40,
                side=0, capacity=25.0 * reps * 2)
        for reps in (8, 10, 12)
    ]
    return Exercise(name="Chest Press", sets=sets, max_weight=25.0, volume=1500.0)


# --- Mapeo puro (sin red) ---

def test_aggregates_sets_reps_and_total_weight_kg():
    session = make_session(
        exercises=[dual_handle_exercise()],
        finished_at=datetime(2026, 9, 18, 8, 15, tzinfo=timezone.utc),
    )
    result = session_to_dict(session, "kg")
    assert result["id"] == "998877"
    assert result["title"] == "Push Day"
    # inicio = 08:15 - 45 min = 07:30 UTC
    assert result["date"] == "2026-09-18T07:30:00Z"
    assert result["durationMinutes"] == 45
    assert result["calories"] == 320
    (ex,) = result["exercises"]
    assert ex == {"name": "Chest Press", "sets": 3, "reps": 10, "weightKg": 50.0}


def test_converts_pounds_to_kg():
    session = make_session(exercises=[dual_handle_exercise()],
                           finished_at=datetime(2026, 9, 18, 8, 15, tzinfo=timezone.utc))
    (ex,) = session_to_dict(session, "lb")["exercises"]
    assert ex["weightKg"] == pytest.approx(50.0 * 0.45359237, abs=0.05)


def test_unloaded_exercise_has_null_weight():
    stretch = Exercise(name="Stretch", sets=[WorkSet(reps=1, target_reps=0, weights=[],
                                                     seconds=60, side=0)])
    session = make_session(exercises=[stretch])
    (ex,) = session_to_dict(session, "kg")["exercises"]
    assert ex["weightKg"] is None
    assert ex["sets"] == 1


def test_free_lift_without_detail_imports_without_exercises():
    session = make_session(exercises=[])
    result = session_to_dict(session, "kg")
    assert result["exercises"] == []
    assert result["date"] == "2026-09-18T12:00:00Z"  # fallback: mediodía UTC


# --- Endpoint (fetch mockeado) ---

@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr("app.main.fetch_workouts", lambda settings, since: [
        session_to_dict(make_session(), "kg")
    ])
    app.dependency_overrides[get_settings] = lambda: TEST_SETTINGS
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_workouts_endpoint_shape(client):
    response = client.get("/speediance/workouts", headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    body = response.json()
    assert body["workouts"][0]["id"] == "998877"


def test_workouts_passes_since_param(client, monkeypatch):
    seen = {}

    def fake_fetch(settings, since):
        seen["since"] = since
        return []

    monkeypatch.setattr("app.main.fetch_workouts", fake_fetch)
    client.get("/speediance/workouts?since=2026-09-01", headers={"X-API-Key": "secret"})
    assert seen["since"] == date(2026, 9, 1)


def test_workouts_rejects_wrong_api_key(client):
    response = client.get("/speediance/workouts", headers={"X-API-Key": "wrong"})
    assert response.status_code == 401
