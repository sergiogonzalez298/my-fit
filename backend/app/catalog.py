"""Resolución de nombres de ejercicio a actionLibraryId, bajo demanda y cacheada.

El catálogo completo son ~900 ejercicios y el detalle cuesta 1 petición por grupo,
así que solo se resuelven los ejercicios que realmente llegan en rutinas.
"""
from __future__ import annotations

import difflib
import json
import unicodedata
from pathlib import Path
from typing import Any


def normalize(name: str) -> str:
    """Minúsculas, sin acentos, espacios colapsados."""
    nfkd = unicodedata.normalize("NFKD", name)
    ascii_name = "".join(c for c in nfkd if not unicodedata.combining(c))
    return " ".join(ascii_name.lower().split())


class ExerciseResolver:
    """Resuelve nombres de ejercicio contra el catálogo Speediance.

    `client` es duck-typed: necesita `exercise_groups()` y `exercise_group(id)`.
    El cache en disco mapea nombre normalizado -> resolución y solo crece.
    """

    def __init__(self, client: Any, cache_path: Path) -> None:
        self._client = client
        self._cache_path = cache_path
        self._cache: dict[str, dict[str, Any]] = self._load_cache()
        self._groups: list[Any] | None = None

    def _load_cache(self) -> dict[str, dict[str, Any]]:
        try:
            return json.loads(self._cache_path.read_text())
        except (FileNotFoundError, json.JSONDecodeError):
            return {}

    def _save_cache(self) -> None:
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        self._cache_path.write_text(json.dumps(self._cache, indent=2))

    def resolve_all(self, names: list[str]) -> tuple[dict[str, dict[str, Any]], list[str]]:
        """Resuelve cada nombre. Devuelve (mapa nombre-normalizado -> info, no resueltos)."""
        resolved: dict[str, dict[str, Any]] = {}
        unmatched: list[str] = []
        for name in names:
            info = self._resolve_one(name)
            if info is None:
                unmatched.append(name)
            else:
                resolved[normalize(name)] = info
        return resolved, unmatched

    def _resolve_one(self, name: str) -> dict[str, Any] | None:
        key = normalize(name)
        if key in self._cache:
            return self._cache[key]

        groups = self._get_groups()
        by_title = {normalize(g.title): g for g in groups}

        group = by_title.get(key)
        if group is None:
            prefix = [g for t, g in by_title.items() if t.startswith(key)]
            if len(prefix) == 1:
                group = prefix[0]
        if group is None:
            close = difflib.get_close_matches(key, list(by_title), n=1, cutoff=0.85)
            if close:
                group = by_title[close[0]]
        if group is None:
            return None

        detail = self._client.exercise_group(group.id)
        entries = [a for a in detail.get("actionLibraryList") or []
                   if a.get("isDisplay", 1) == 1]
        if not entries:
            return None

        info = {
            "actionLibraryId": entries[0]["id"],
            "title": group.title,
            "isLeftRight": bool(detail.get("isLeftRight")),
            "isBarbell": bool(detail.get("isBarbell")),
        }
        self._cache[key] = info
        self._save_cache()
        return info

    def _get_groups(self) -> list[Any]:
        if self._groups is None:
            self._groups = self._client.exercise_groups()
        return self._groups
