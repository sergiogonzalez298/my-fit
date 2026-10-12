"""Resolución de nombres de ejercicio a título canónico + imagen (solo lectura).

Sirve a la tarjeta de rutina del chat: la app manda los nombres que propuso la IA
y recibe título canónico e imagen oficial para mostrarlos antes de subir nada.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from speediance import Credentials, SpeedianceClient

from .catalog import ExerciseResolver, normalize
from .config import Settings

_CACHE = Path(__file__).resolve().parent.parent / ".cache" / "exercises.json"


def _cache_path() -> Path:
    return _CACHE


def _make_client(settings: Settings) -> SpeedianceClient:
    """Cliente de solo lectura (sin allow_writes)."""
    return SpeedianceClient(
        Credentials(email=settings.email, password=settings.password,
                    region=settings.region),
    )


def resolve_exercises(settings: Settings, names: list[str]) -> list[dict[str, Any]]:
    """Por cada nombre: título canónico e imagen si se resuelve, o resolved=False."""
    with _make_client(settings) as client:
        client.login()
        resolver = ExerciseResolver(client, cache_path=_cache_path())
        resolved, _ = resolver.resolve_all(names)

    return [
        {
            "name": name,
            "resolved": (info := resolved.get(normalize(name))) is not None,
            "title": info["title"] if info else None,
            "image": info.get("image") if info else None,
        }
        for name in names
    ]
