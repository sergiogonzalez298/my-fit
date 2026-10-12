"""Creación de plantillas de entrenamiento en Speediance (ESCRITURA).

Único módulo del backend que escribe: el cliente se construye con
allow_writes=True aquí y en ningún otro sitio.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from speediance import Credentials, SpeedianceClient
from speediance.errors import SpeedianceAPIError

from .catalog import ExerciseResolver, normalize
from .config import Settings

_CACHE = Path(__file__).resolve().parent.parent / ".cache" / "exercises.json"


def _cache_path() -> Path:
    return _CACHE


def _make_write_client(settings: Settings) -> SpeedianceClient:
    return SpeedianceClient(
        Credentials(email=settings.email, password=settings.password,
                    region=settings.region),
        allow_writes=True,
    )


class UnmatchedExercises(Exception):
    def __init__(self, names: list[str]) -> None:
        super().__init__(", ".join(names))
        self.names = names


def _find_by_name(client: Any, name: str) -> Any | None:
    wanted = normalize(name.strip())
    for template in client.list_templates():
        if normalize(template.name.strip()) == wanted:
            return template
    return None


def upload_template(settings: Settings, name: str, movements: list[dict]) -> dict:
    """Crea la plantilla en Speediance. Idempotente por nombre.

    Quirk del E2E: la API puede responder code 10 'Parameter error' aun habiendo
    creado la plantilla — se confirma siempre por listado.
    """
    with _make_write_client(settings) as client:
        client.login()

        resolver = ExerciseResolver(client, cache_path=_cache_path())
        resolved, unmatched = resolver.resolve_all(
            [m["exerciseName"] for m in movements])
        if unmatched:
            raise UnmatchedExercises(unmatched)

        existing = _find_by_name(client, name)
        if existing is not None:
            return {"code": str(existing.code), "name": existing.name,
                    "movementCount": existing.action_count, "deduplicated": True}

        lib_movements = [
            {
                "action_library_id": resolved[normalize(m["exerciseName"])]["actionLibraryId"],
                "is_left_right": resolved[normalize(m["exerciseName"])]["isLeftRight"],
                "sets": [
                    {"reps": s["reps"], "weight": s["weightKg"],
                     "rest_seconds": s.get("restSeconds", 60)}
                    for s in m["sets"]
                ],
            }
            for m in movements
        ]

        try:
            code = client.create_template(name, lib_movements)
        except SpeedianceAPIError as exc:
            if exc.code != 10:
                raise
            confirmed = _find_by_name(client, name)
            if confirmed is None:
                raise
            code = confirmed.code

        # Confirmación por listado incluso en el camino feliz (quirk del spike).
        confirmed = _find_by_name(client, name)
        if confirmed is not None:
            return {"code": str(confirmed.code), "name": confirmed.name,
                    "movementCount": confirmed.action_count, "deduplicated": False}
        return {"code": str(code), "name": name,
                "movementCount": len(movements), "deduplicated": False}
