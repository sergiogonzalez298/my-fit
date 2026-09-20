"""Acceso a Speediance a través de la librería no oficial `speediance`."""
from __future__ import annotations

from .config import Settings


def check_speediance(settings: Settings) -> None:
    """Verifica que el login contra Speediance funciona. Lanza excepción si no."""
    from speediance import Credentials, SpeedianceClient

    with SpeedianceClient(
        Credentials(email=settings.email, password=settings.password, region=settings.region)
    ) as client:
        client.login()


from datetime import date, datetime, timedelta, timezone

from speediance import Credentials, SpeedianceClient
from speediance.models import TrainingSession

_LB_TO_KG = 0.45359237


def _start_of(session: TrainingSession) -> datetime:
    """Inicio de la sesión en UTC (para casar con el registro de HealthKit)."""
    if session.finished_at is not None:
        end = session.finished_at
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)
        return end - timedelta(minutes=session.duration_min)
    return datetime(session.day.year, session.day.month, session.day.day,
                    12, 0, tzinfo=timezone.utc)


def session_to_dict(session: TrainingSession, unit: str) -> dict:
    """Una sesión de Speediance como dict del formato propio del backend."""
    to_kg = 1.0 if unit == "kg" else _LB_TO_KG
    exercises = []
    for e in session.exercises:
        if not e.sets:
            continue
        weight = round(e.max_weight * e.load_points * to_kg, 1) if e.is_loaded else None
        exercises.append({
            "name": e.name,
            "sets": len(e.sets),
            "reps": round(e.total_reps / len(e.sets)),
            "weightKg": weight,
        })
    return {
        "id": str(session.training_id),
        "title": session.title,
        "date": _start_of(session).isoformat().replace("+00:00", "Z"),
        "durationMinutes": int(session.duration_min),
        "calories": int(session.calories),
        "exercises": exercises,
    }


def fetch_workouts(settings: Settings, since: date | None) -> list[dict]:
    """Sesiones completadas desde `since` (o todo el historial) en nuestro formato.

    Ojo: la librería se pasea a 1 petición/segundo y gasta una por sesión;
    la primera importación completa puede tardar varios minutos.
    """
    start = since or date(2000, 1, 1)
    with SpeedianceClient(
        Credentials(email=settings.email, password=settings.password, region=settings.region)
    ) as client:
        client.login()
        sessions = client.history_sessions(start, date.today(), with_detail=True)
        unit = client.unit
    return [session_to_dict(s, unit) for s in sessions]
