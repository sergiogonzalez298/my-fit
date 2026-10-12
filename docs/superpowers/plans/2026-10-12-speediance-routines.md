# Fase 3 — Rutinas por IA a la Gym Monster · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El usuario pide una rutina al NutriCoach en el chat, la IA la propone como tarjeta estructurada, y un botón la sube como plantilla a la Gym Monster 2 vía el backend local.

**Architecture:** Backend FastAPI existente gana resolución de nombres de ejercicio bajo demanda (`ExerciseResolver`, cache incremental en disco) y `POST /speediance/templates` con dedup por nombre y confirmación por listado (quirk del code 10). La app parsea el bloque JSON `routine` de las respuestas del coach (`RoutineParser`), la muestra como `RoutineCardView` en el chat y la sube con `BackendService.uploadTemplate`.

**Tech Stack:** Python 3.11+ (FastAPI, librería `speediance` pineada, pytest) · Swift 6 / SwiftUI / SwiftData (iOS 17+) · Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-11-speediance-routines-design.md`

## Global Constraints

- Mismas del plan Fase 1: iOS 17+, Swift 6, Swift Testing (no XCTest), sin dependencias nuevas en iOS; backend Python con deps ya instaladas (`fastapi`, `uvicorn`, `speediance` pin git, `pytest`, `httpx`); mensajes en español.
- Tras crear archivos Swift nuevos: `xcodegen generate` y commitear `project.pbxproj`.
- Tests iOS: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet [-only-testing:...]`; backend: `cd backend && .venv/bin/python -m pytest tests/ -v`.
- La escritura a Speediance SOLO en el módulo nuevo del backend (`allow_writes=True` solo ahí); el resto del backend sigue read-only.
- Pesos POR MANGO en kg (criterio validado en Fase 1).
- Credenciales solo en `backend/.env`. El cliente iOS usa el mismo header `X-API-Key`.
- Quirk obligatorio: tras `create_template`, confirmar listando plantillas aunque la llamada no falle, y tratar `SpeedianceAPIError` code 10 como "posiblemente creada" → confirmar por listado.
- El chat nunca se rompe por JSON malformado: si el parseo falla, se muestra solo texto.

## Review Focus

1. **La IA inventa un ejercicio inexistente** → el backend debe responder 422 con `{"detail": {"unmatched": [...]}}` y NO crear nada. → test en Task 2.
2. **Reintento de subida** (doble tap, reintento tras error) → idempotente: si ya existe plantilla con ese nombre, se devuelve éxito con su `code` sin duplicar. → test en Task 2.
3. **Code 10 pero creada** (quirk del spike) → confirmar por `list_templates` antes de reportar error. → test en Task 2.
4. **JSON malformado o parcial de la IA** → `RoutineParser` devuelve rutina nil y el texto íntegro; el chat no muestra tarjeta rota. → test en Task 3.
5. **Ejercicio unilateral** (`isLeftRight`) sin `side` explícito → el backend pasa `is_left_right` a la librería, que alterna lados sola (fault 2 de writes.py). → test en Task 2.

---

### Task 1: Backend — `ExerciseResolver` (resolución de nombres bajo demanda)

**Files:**
- Create: `backend/app/catalog.py`
- Create: `backend/tests/test_catalog.py`
- Modify: `.gitignore` (añadir `backend/.cache/`)

**Interfaces:**
- Consumes: `Settings` de `app/config.py` (Task 1 de Fase 1).
- Produces: `class ExerciseResolver(client, cache_path: Path)` con `resolve_all(names: list[str]) -> tuple[dict[str, dict], list[str]]` (mapa nombre-normalizado → `{actionLibraryId, title, isLeftRight, isBarbell}` + lista de no resueltos) y `normalize(name: str) -> str`. El `client` es cualquier objeto con `exercise_groups() -> list` y `exercise_group(id) -> dict` (duck-typed para tests).

- [ ] **Step 1: Escribir los tests que fallan**

`backend/tests/test_catalog.py`:
```python
import pytest

from app.catalog import ExerciseResolver, normalize


class FakeGroup:
    def __init__(self, id, title):
        self.id = id
        self.title = title


class FakeClient:
    """Duck-type del SpeedianceClient para el resolver."""
    def __init__(self, groups, details):
        self._groups = groups
        self._details = details  # group_id -> detalle
        self.detail_calls = 0

    def exercise_groups(self):
        return self._groups

    def exercise_group(self, group_id):
        self.detail_calls += 1
        return self._details[group_id]


def make_client():
    groups = [
        FakeGroup(116, "Barbell Bench Press"),
        FakeGroup(200, "Dual-Handle Zottman Curl"),
        FakeGroup(300, "Standing Dual-Handle Hammer Curl"),
    ]
    details = {
        116: {"isLeftRight": 0, "isBarbell": 1,
              "actionLibraryList": [{"id": 424195710320641, "isDisplay": 1}]},
        200: {"isLeftRight": 1, "isBarbell": 0,
              "actionLibraryList": [{"id": 999001, "isDisplay": 1}]},
        300: {"isLeftRight": 0, "isBarbell": 0,
              "actionLibraryList": [{"id": 999002, "isDisplay": 1}]},
    }
    return FakeClient(groups, details)


def test_normalize_strips_accents_and_case():
    assert normalize("  Bíceps  Curl ") == "biceps curl"
    assert normalize("Barbell Bench Press") == "barbell bench press"


def test_exact_match_resolves(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Barbell Bench Press"])
    assert unmatched == []
    assert resolved["barbell bench press"]["actionLibraryId"] == 424195710320641
    assert resolved["barbell bench press"]["isBarbell"] is True
    assert resolved["barbell bench press"]["isLeftRight"] is False


def test_accent_insensitive_match(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["bárbell bench press"])
    assert unmatched == []
    assert "barbell bench press" in resolved


def test_prefix_match(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Dual-Handle Zottman"])
    assert unmatched == []
    assert resolved["dual-handle zottman"]["actionLibraryId"] == 999001
    assert resolved["dual-handle zottman"]["isLeftRight"] is True


def test_fuzzy_match(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Barbell Bench Pres"])  # falta una s
    assert unmatched == []
    assert "barbell bench pres" in resolved


def test_unmatched_name_is_reported(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Encogimiento Quantum 3000"])
    assert resolved == {}
    assert unmatched == ["Encogimiento Quantum 3000"]


def test_cache_avoids_second_detail_call(tmp_path):
    client = make_client()
    cache = tmp_path / "c.json"
    ExerciseResolver(client, cache_path=cache).resolve_all(["Barbell Bench Press"])
    resolver2 = ExerciseResolver(make_client(), cache_path=cache)
    resolved, _ = resolver2.resolve_all(["Barbell Bench Press"])
    assert resolved  # viene del cache
    assert resolver2._client.detail_calls == 0
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `cd backend && .venv/bin/python -m pytest tests/test_catalog.py -v`
Expected: FAIL con `ModuleNotFoundError: No module named 'app.catalog'`

- [ ] **Step 3: Implementar `catalog.py`**

```python
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
            if prefix:
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
```

- [ ] **Step 4: Ejecutar y ver que pasa + gitignore**

```bash
echo "backend/.cache/" >> .gitignore
cd backend && .venv/bin/python -m pytest tests/test_catalog.py -v
```
Expected: 7 passed

- [ ] **Step 5: Commit**

```bash
git add backend/app/catalog.py backend/tests/test_catalog.py .gitignore
git commit -m "feat(backend): ExerciseResolver con cache incremental y matching exacto/prefijo/fuzzy"
```

---

### Task 2: Backend — `POST /speediance/templates`

**Files:**
- Create: `backend/app/templates.py`
- Create: `backend/tests/test_templates.py`
- Modify: `backend/app/main.py`
- Modify: `backend/README.md` (añadir el endpoint)

**Interfaces:**
- Consumes: Task 1 (`ExerciseResolver`, `normalize`), Task 1 Fase 1 (`get_settings`, `verify_api_key`, app FastAPI).
- Produces: `class UnmatchedExercises(Exception)` con `.names: list[str]`; `upload_template(settings: Settings, name: str, movements: list[dict]) -> dict` devolviendo `{"code": str, "name": str, "movementCount": int, "deduplicated": bool}`. Endpoint: `POST /speediance/templates` con body `{"name": str, "movements": [{"exerciseName": str, "sets": [{"reps": int, "weightKg": float, "restSeconds": int (opcional, defecto 60)}]}]}`; respuestas 200 / 422 `{"detail": {"unmatched": [...]}}` / 502.

- [ ] **Step 1: Escribir los tests que fallan**

`backend/tests/test_templates.py`:
```python
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
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `cd backend && .venv/bin/python -m pytest tests/test_templates.py -v`
Expected: FAIL con `ModuleNotFoundError: No module named 'app.templates'`

- [ ] **Step 3: Implementar `templates.py`**

```python
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
```

- [ ] **Step 4: Endpoint en `main.py`**

Añadir al principio de `backend/app/main.py`:
```python
from pydantic import BaseModel

from .templates import UnmatchedExercises, upload_template
```

Y al final del archivo:
```python
class SetIn(BaseModel):
    reps: int
    weightKg: float
    restSeconds: int = 60


class MovementIn(BaseModel):
    exerciseName: str
    sets: list[SetIn]


class TemplateIn(BaseModel):
    name: str
    movements: list[MovementIn]


@app.post("/speediance/templates", dependencies=[Depends(verify_api_key)])
def create_speediance_template(
    body: TemplateIn,
    settings: Settings = Depends(get_settings),
) -> dict:
    try:
        return upload_template(settings, body.name,
                               [m.model_dump() for m in body.movements])
    except UnmatchedExercises as exc:
        raise HTTPException(status_code=422,
                            detail={"unmatched": exc.names})
    except Exception as exc:
        raise HTTPException(status_code=502,
                            detail=f"Error al crear la plantilla: {exc}")
```

- [ ] **Step 5: README y tests verdes**

Añadir al final de la sección Endpoints de `backend/README.md`:
```markdown
- `POST /speediance/templates` — **escritura**: crea una plantilla de entreno
  (aparece en la app de Speediance y en la máquina). Body:
  `{"name": "...", "movements": [{"exerciseName": "...", "sets": [{"reps": 10, "weightKg": 45.0, "restSeconds": 90}]}]}`.
  Los nombres se resuelven contra el catálogo (exacto > prefijo > fuzzy);
  los no reconocidos devuelven 422 con `{"detail": {"unmatched": [...]}}`.
  Idempotente por nombre: subir dos veces la misma rutina no duplica.
```

Run: `cd backend && .venv/bin/python -m pytest tests/ -v`
Expected: todos passed (los de antes + 6 nuevos + 7 de catálogo)

- [ ] **Step 6: Commit**

```bash
git add backend/app/templates.py backend/tests/test_templates.py backend/app/main.py backend/README.md
git commit -m "feat(backend): POST /speediance/templates con resolución de ejercicios e idempotencia"
```

---

### Task 3: iOS — `RoutineProposal` + `RoutineParser`

**Files:**
- Create: `MyFit/Models/RoutineProposal.swift`
- Create: `MyFit/Services/RoutineParser.swift`
- Test: `MyFitTests/RoutineParserTests.swift`

**Interfaces:**
- Consumes: nada de tasks anteriores de esta fase.
- Produces: `struct RoutineProposal: Codable, Equatable, Sendable` con `name: String`, `movements: [Movement]`; `Movement{exerciseName: String, sets: [Set]}`; `Set{reps: Int, weightKg: Double, restSeconds: Int}` (los mismos nombres camelCase que el backend — Task 4 los reenvía tal cual). Y `RoutineParser.extract(from: String) -> (displayText: String, routine: RoutineProposal?)`, usado por Task 6.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/RoutineParserTests.swift`:
```swift
import Foundation
import Testing
@testable import MyFit

@Suite("RoutineParser · extracción del bloque routine")
struct RoutineParserTests {

    private let validJSON = """
    {"routine": {"name": "Empuje semana 42", "movements": [
      {"exerciseName": "Barbell Bench Press",
       "sets": [{"reps": 10, "weightKg": 45.0, "restSeconds": 90}]},
      {"exerciseName": "Dual-Handle Zottman Curl",
       "sets": [{"reps": 12, "weightKg": 9.0, "restSeconds": 60},
                {"reps": 12, "weightKg": 9.0, "restSeconds": 60}]}
    ]}}
    """

    @Test("extrae la rutina y deja el texto limpio")
    func extractsRoutineAndText() {
        let text = "Aquí tienes tu rutina de empuje 💪\n\n```json\n" + validJSON + "\n```"
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(display == "Aquí tienes tu rutina de empuje 💪")
        let r = try? #require(routine)
        #expect(r?.name == "Empuje semana 42")
        #expect(r?.movements.count == 2)
        #expect(r?.movements.first?.sets.first?.weightKg == 45.0)
        #expect(r?.movements.first?.sets.first?.restSeconds == 90)
    }

    @Test("acepta el JSON sin fence markdown")
    func extractsBareJSON() {
        let (display, routine) = RoutineParser.extract(from: "Toma.\n" + validJSON)
        #expect(display == "Toma.")
        #expect(routine != nil)
    }

    @Test("JSON malformado devuelve rutina nil y el texto íntegro")
    func malformedJSONKeepsFullText() {
        let text = "Mira esto: {\"routine\": {\"name\": \"roto\", \"movements\": ["
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine == nil)
        #expect(display == text)
    }

    @Test("JSON válido sin clave routine no produce tarjeta")
    func jsonWithoutRoutineKeyIsIgnored() {
        let text = "Datos: {\"foo\": 1}"
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine == nil)
        #expect(display == text)
    }

    @Test("texto sin JSON pasa intacto")
    func plainTextPassesThrough() {
        let text = "Hoy te toca comer pollo con arroz."
        let (display, routine) = RoutineParser.extract(from: text)
        #expect(routine == nil)
        #expect(display == text)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/RoutineParserTests`
Expected: FAIL de compilación (`cannot find 'RoutineParser'`)

- [ ] **Step 3: Implementar los dos archivos**

`MyFit/Models/RoutineProposal.swift`:
```swift
import Foundation

/// Rutina de fuerza propuesta por el coach, pendiente de subir a la Speediance.
/// Los nombres de campos son el contrato exacto del backend (POST /speediance/templates).
struct RoutineProposal: Codable, Equatable, Sendable {
    var name: String
    var movements: [Movement]

    struct Movement: Codable, Equatable, Sendable {
        var exerciseName: String
        var sets: [Set]
    }

    struct Set: Codable, Equatable, Sendable {
        var reps: Int
        var weightKg: Double
        var restSeconds: Int
    }
}
```

`MyFit/Services/RoutineParser.swift`:
```swift
import Foundation

enum RoutineParser {
    private struct Wrapper: Decodable { let routine: RoutineProposal }

    /// Extrae un bloque {"routine": ...} de la respuesta del coach.
    /// Devuelve el texto visible (sin el bloque) y la rutina si es válida.
    /// Si el JSON está malformado o no tiene clave "routine", el texto pasa intacto.
    static func extract(from text: String) -> (displayText: String, routine: RoutineProposal?) {
        // Camino 1: fence ```json ... ``` (o ``` a secas)
        if let fenceStart = text.range(of: "```"),
           let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            var body = String(text[fenceStart.upperBound..<fenceEnd.lowerBound])
            if body.hasPrefix("json") { body = String(body.dropFirst(4)) }
            if let proposal = decode(body) {
                let display = String(text[..<fenceStart.lowerBound]) +
                              String(text[fenceEnd.upperBound...])
                return (display.trimmingCharacters(in: .whitespacesAndNewlines), proposal)
            }
        }
        // Camino 2: JSON suelto del primer '{' al último '}'
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
           start < end {
            let candidate = String(text[start...end])
            if let proposal = decode(candidate) {
                let display = String(text[..<start]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (display, proposal)
            }
        }
        return (text, nil)
    }

    private static func decode(_ json: String) -> RoutineProposal? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Wrapper.self, from: data).routine
    }
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/RoutineParserTests`
Expected: 5 tests passed

- [ ] **Step 5: Commit**

```bash
git add MyFit/Models/RoutineProposal.swift MyFit/Services/RoutineParser.swift MyFitTests/RoutineParserTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: RoutineProposal y parser del bloque routine del coach"
```

---

### Task 4: iOS — `BackendService.uploadTemplate`

**Files:**
- Modify: `MyFit/Services/BackendService.swift`
- Test: `MyFitTests/BackendUploadTests.swift`

**Interfaces:**
- Consumes: Task 3 (`RoutineProposal`), Task 4 de Fase 1 (`BackendService`, `BackendError`, `makeRequest` — que es `private`: este task lo amplía dentro del mismo archivo).
- Produces: `struct UploadTemplateResponse: Decodable, Sendable { code, name, movementCount, deduplicated }`; `BackendServing.uploadTemplate(_ routine: RoutineProposal) async throws -> UploadTemplateResponse`; nuevo caso `BackendError.unmatchedExercises([String])`.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/BackendUploadTests.swift`:
```swift
import Foundation
import Testing
@testable import MyFit

@Suite("BackendService · subida de plantillas")
struct BackendUploadTests {

    @Test("el body de subida usa el contrato exacto del backend")
    func requestBodyMatchesContract() throws {
        let routine = RoutineProposal(name: "Empuje", movements: [
            RoutineProposal.Movement(exerciseName: "Barbell Bench Press", sets: [
                RoutineProposal.Set(reps: 10, weightKg: 45.0, restSeconds: 90),
            ]),
        ])
        let data = try JSONEncoder().encode(routine)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["name"] as? String == "Empuje")
        let movements = json["movements"] as! [[String: Any]]
        #expect(movements[0]["exerciseName"] as? String == "Barbell Bench Press")
        let sets = movements[0]["sets"] as! [[String: Any]]
        #expect(sets[0]["reps"] as? Int == 10)
        #expect(sets[0]["weightKg"] as? Double == 45.0)
        #expect(sets[0]["restSeconds"] as? Int == 90)
    }

    @Test("la respuesta OK decodifica code/name/movementCount/deduplicated")
    func decodesUploadResponse() throws {
        let json = """
        {"code": "abc123", "name": "Empuje", "movementCount": 5, "deduplicated": false}
        """
        let response = try JSONDecoder().decode(UploadTemplateResponse.self,
                                                from: Data(json.utf8))
        #expect(response.code == "abc123")
        #expect(response.movementCount == 5)
        #expect(response.deduplicated == false)
    }

    @Test("un 422 con unmatched se convierte en BackendError.unmatchedExercises")
    func decodesUnmatchedError() throws {
        let body = #"{"detail": {"unmatched": ["Encogimiento Quantum 3000"]}}"#
        let names = BackendService.parseUnmatched(from: Data(body.utf8))
        #expect(names == ["Encogimiento Quantum 3000"])
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/BackendUploadTests`
Expected: FAIL de compilación (`cannot find 'UploadTemplateResponse'`)

- [ ] **Step 3: Implementar en `BackendService.swift`**

a) Nuevo caso de error en `BackendError`:
```swift
    case unmatchedExercises([String])
```
y su descripción en el switch:
```swift
        case .unmatchedExercises(let names):
            return "No reconozco estos ejercicios: \(names.joined(separator: ", ")). Díselo al coach para corregir la rutina."
```

b) Nuevos DTOs y extensión del protocolo (después de `BackendWorkoutsResponse`):
```swift
struct UploadTemplateResponse: Decodable, Sendable {
    let code: String
    let name: String
    let movementCount: Int
    let deduplicated: Bool
}
```
En el protocolo `BackendServing`, añadir:
```swift
    /// Sube una rutina como plantilla a Speediance. Idempotente por nombre.
    func uploadTemplate(_ routine: RoutineProposal) async throws -> UploadTemplateResponse
```

c) En `BackendService`, añadir:
```swift
    /// Extrae los nombres no resueltos de un 422 del backend. Internal para tests.
    static func parseUnmatched(from data: Data) -> [String]? {
        struct ErrorBody: Decodable {
            struct Detail: Decodable { let unmatched: [String] }
            let detail: Detail
        }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).detail.unmatched
    }

    func uploadTemplate(_ routine: RoutineProposal) async throws -> UploadTemplateResponse {
        var request = try makeRequest(path: "speediance/templates")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(routine)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        if http.statusCode == 422, let names = Self.parseUnmatched(from: data) {
            throw BackendError.unmatchedExercises(names)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpError(status: http.statusCode,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(UploadTemplateResponse.self, from: data)
    }
```

d) `StubBackend` en `SpeedianceImporterTests.swift` y `RecordingBackend` dejarán de compilar si no conforman el nuevo método: añadir a AMBOS stubs:
```swift
    func uploadTemplate(_ routine: RoutineProposal) async throws -> UploadTemplateResponse {
        UploadTemplateResponse(code: "stub", name: routine.name,
                               movementCount: routine.movements.count, deduplicated: false)
    }
```

- [ ] **Step 4: Ejecutar toda la suite**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: toda la suite passed (los stubs de la Task 5 de Fase 1 actualizados compilan)

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/BackendService.swift MyFitTests/BackendUploadTests.swift MyFitTests/SpeedianceImporterTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: BackendService.uploadTemplate con manejo de ejercicios no reconocidos"
```

---

### Task 5: iOS — contexto de fuerza y prompt de rutinas en el coach

**Files:**
- Modify: `MyFit/Services/NutritionChatService.swift` (bloque "Últimos entrenos", líneas 242-256; system prompt, líneas 107-121)
- Test: `MyFitTests/CoachStrengthContextTests.swift`

**Interfaces:**
- Consumes: modelo `Workout`/`Exercise` existente.
- Produces: `NutritionChatService.formatStrengthContext(_ workouts: [Workout]) -> [String]` (internal, testeable) — líneas de detalle de fuerza para el prompt.

- [ ] **Step 1: Escribir el test que falla**

`MyFitTests/CoachStrengthContextTests.swift`:
```swift
import Foundation
import Testing
@testable import MyFit

@Suite("NutritionChatService · contexto de fuerza")
struct CoachStrengthContextTests {

    @Test("los entrenos con ejercicios muestran el detalle de fuerza")
    func includesExerciseDetail() {
        let workout = Workout(date: Date(), type: .strength, durationMinutes: 45,
                              caloriesBurned: 300,
                              exercises: [
                                  Exercise(name: "Bench Press", sets: 4, reps: 8, weightKg: 60.0),
                                  Exercise(name: "Stretch", sets: 1, reps: 1, weightKg: nil),
                              ])
        let lines = NutritionChatService.formatStrengthContext([workout])
        let joined = lines.joined(separator: "\n")
        #expect(joined.contains("Bench Press 4x8 @ 60 kg"))
        #expect(joined.contains("Stretch 1x1"))
        #expect(!joined.contains("Stretch 1x1 @"))
    }

    @Test("sin entrenos con ejercicios no hay sección de detalle")
    func emptyWhenNoExercises() {
        let workout = Workout(date: Date(), type: .cardio, durationMinutes: 30)
        let lines = NutritionChatService.formatStrengthContext([workout])
        #expect(lines.allSatisfy { !$0.contains("Ejercicios:") })
    }

    @Test("como mucho 10 ejercicios por entreno")
    func capsExercisesPerWorkout() {
        let exercises = (1...15).map { Exercise(name: "Ej\($0)", sets: 3, reps: 10, weightKg: 20.0) }
        let workout = Workout(date: Date(), exercises: exercises)
        let lines = NutritionChatService.formatStrengthContext([workout])
        let detail = lines.first { $0.contains("Ejercicios:") } ?? ""
        #expect(detail.contains("Ej10"))
        #expect(!detail.contains("Ej11"))
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CoachStrengthContextTests`
Expected: FAIL de compilación (`formatStrengthContext` no existe)

- [ ] **Step 3: Implementar**

a) En `NutritionChatService.swift`, sustituir el bloque "// Últimos entrenos" (líneas 242-256) por:

```swift
        // Últimos entrenos (con detalle de fuerza cuando lo hay — importado de Speediance)
        var workoutsDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        workoutsDescriptor.fetchLimit = 5
        if let workouts = try? context.fetch(workoutsDescriptor), !workouts.isEmpty {
            lines.append("- Últimos entrenos:")
            for workout in workouts {
                var line = "  · \(workout.type.displayName) (\(dayFmt.string(from: workout.date)), \(workout.durationMinutes) min)"
                if let kcal = workout.caloriesBurned {
                    line += " · \(kcal) kcal"
                }
                lines.append(line)
            }
            lines.append(contentsOf: Self.formatStrengthContext(workouts))
        }
```

b) Añadir el método internal (no `private`, para que los tests lo vean con `@testable`):

```swift
    /// Detalle de fuerza por entreno (pesos por mango, como en Speediance). Máx. 10 ejercicios.
    static func formatStrengthContext(_ workouts: [Workout]) -> [String] {
        var lines: [String] = []
        for workout in workouts where !workout.exercises.isEmpty {
            let detail = workout.exercises.prefix(10).map { exercise in
                var s = "\(exercise.name) \(exercise.sets)x\(exercise.reps)"
                if let weight = exercise.weightKg {
                    s += " @ \(weight.formatted(.number.precision(.fractionLength(0...1)))) kg"
                }
                return s
            }.joined(separator: ", ")
            lines.append("    Ejercicios: \(detail)")
        }
        return lines
    }
```

c) Ampliar el system prompt (tras el bloque "Normas:", antes del `return prompt`):

```swift
        prompt += "\n\n" + """
        Rutinas de fuerza (Speediance):
        - Si el usuario te pide una rutina de entrenamiento, propónla con tu comentario habitual y, AL FINAL, un bloque ```json con este formato exacto:
        {"routine": {"name": "...", "movements": [{"exerciseName": "...", "sets": [{"reps": 10, "weightKg": 45.0, "restSeconds": 90}]}]}}
        - exerciseName en inglés, tal como aparece en su historial de entrenos de arriba; para ejercicios nuevos usa el nombre estándar del catálogo Speediance
        - Pesos en kg POR MANGO (como en su historial), realistas según sus marcas recientes
        - 4-8 ejercicios por rutina, 2-4 series por ejercicio, descansos de 60-120 s
        - Si no te piden rutina, no incluyas el bloque json
        """
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: toda la suite passed

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/NutritionChatService.swift MyFitTests/CoachStrengthContextTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: el coach ve el detalle de fuerza y puede proponer rutinas estructuradas"
```

---

### Task 6: iOS — `RoutineCardView` e integración en el chat

**Files:**
- Create: `MyFit/Views/Assistant/RoutineCardView.swift`
- Modify: `MyFit/Views/Assistant/NutritionChatView.swift` (MessageBubble, líneas 173-201)

**Interfaces:**
- Consumes: Task 3 (`RoutineParser.extract`, `RoutineProposal`), Task 4 (`BackendService.fromStoredConfiguration()`, `uploadTemplate`, `BackendError`).
- Produces: `RoutineCardView(routine: RoutineProposal)`.

- [ ] **Step 1: Crear `RoutineCardView.swift`**

```swift
import SwiftUI

/// Tarjeta de rutina propuesta por el coach, con subida a la Speediance.
struct RoutineCardView: View {
    let routine: RoutineProposal

    private enum UploadState: Equatable {
        case idle, uploading, uploaded(String), failed(String)
    }
    @State private var state: UploadState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(routine.name, systemImage: "dumbbell.fill")
                .font(.subheadline.bold())

            ForEach(Array(routine.movements.enumerated()), id: \.offset) { _, movement in
                let first = movement.sets.first
                HStack {
                    Text(movement.exerciseName)
                        .font(.caption)
                    Spacer()
                    Text("\(movement.sets.count)x\(first?.reps ?? 0)" +
                         (first.map { " @ \($0.weightKg.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            switch state {
            case .idle:
                Button {
                    Task { await upload() }
                } label: {
                    Label("Subir a la máquina", systemImage: "arrow.up.to.line")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            case .uploading:
                HStack { Spacer(); ProgressView(); Text("Subiendo…").font(.caption); Spacer() }
            case .uploaded(let name):
                Label("'\(name)' ya está en tu Speediance ✅", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text("❌ \(message)")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Reintentar") { Task { await upload() } }
                        .font(.caption.bold())
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func upload() async {
        guard let backend = BackendService.fromStoredConfiguration() else {
            state = .failed("Configura el backend en Ajustes > Speediance primero.")
            return
        }
        state = .uploading
        do {
            let result = try await backend.uploadTemplate(routine)
            state = .uploaded(result.name)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Integrar en `MessageBubble` (NutritionChatView.swift)**

Sustituir el `MessageBubble` completo (líneas 173-201) por:

```swift
private struct MessageBubble: View {
    let message: ChatMessage

    /// Solo los mensajes del asistente pueden llevar rutina embebida.
    private var parsed: (displayText: String, routine: RoutineProposal?) {
        message.role == .assistant
            ? RoutineParser.extract(from: message.content)
            : (message.content, nil)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            if message.role == .assistant {
                Image(systemName: "fork.knife.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 8) {
                if !parsed.displayText.isEmpty {
                    Text(parsed.displayText)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            message.role == .user
                                ? Color.green.opacity(0.85)
                                : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                        .foregroundStyle(message.role == .user ? .white : .primary)
                }
                if let routine = parsed.routine {
                    RoutineCardView(routine: routine)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
```

- [ ] **Step 3: Compilar y ejecutar toda la suite**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: build OK, suite passed

- [ ] **Step 4: Commit**

```bash
git add MyFit/Views/Assistant/RoutineCardView.swift MyFit/Views/Assistant/NutritionChatView.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: tarjeta de rutina en el chat con subida a la Gym Monster"
```

---

### Task 7: Verificación E2E

**Files:**
- Modify: `backend/README.md` (si falta algo del flujo)

- [ ] **Step 1: Verificación con el usuario**

1. Backend arrancado (`cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`).
2. Reinstalar la app en el iPhone.
3. En el chat: "créame una rutina de espalda y bíceps para esta semana" → debe llegar comentario + tarjeta con ejercicios reales de su historial.
4. Pulsar "Subir a la máquina" → ✅ con el nombre.
5. Comprobar en la app de Speediance y en la Gym Monster 2 que la plantilla existe y los ejercicios/pesos son los de la tarjeta.
6. Pulsar de nuevo (reintento) → no duplica (deduplicated).
7. Borrar la plantilla de prueba desde la app oficial de Speediance.
