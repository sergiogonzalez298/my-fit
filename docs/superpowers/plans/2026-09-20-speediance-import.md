# Fase 1 — Importación de entrenos Speediance · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Importar a MyFit las sesiones de Speediance con ejercicios agregados (sets × reps × peso) a través de un backend local propio, sin duplicar los entrenos que ya llegan por HealthKit.

**Architecture:** Backend Python (FastAPI) en `backend/` que usa la librería `speediance` (pookey/speediance-cli) y expone una API propia y estable (`GET /health`, `GET /speediance/workouts`). La app iOS habla solo con ese backend mediante un `BackendService` en Swift; `SpeedianceImporter` deduplica por `externalID` y por ventana temporal de 15 minutos contra entrenos existentes.

**Tech Stack:** Python 3.11+ (FastAPI, uvicorn, librería `speediance`, pytest, httpx) · Swift 6 / SwiftUI / SwiftData (iOS 17+) · Swift Testing.

**Spec:** `docs/superpowers/specs/2026-09-20-speediance-import-design.md`

## Global Constraints

- iOS deployment target 17.0, Swift 6 (`SWIFT_STRICT_CONCURRENCY: minimal`), Swift Testing (nada de XCTest).
- La app iOS NO añade dependencias de terceros; solo Foundation/SwiftUI/SwiftData.
- Tras crear cualquier archivo nuevo en `MyFit/` o `MyFitTests/`, ejecutar `xcodegen generate` para regenerar el proyecto (los sources se incluyen por carpeta, pero el `.xcodeproj` debe regenerarse).
- Mensajes de error y texto de UI en español, siguiendo el estilo de `AIServiceError` y `SettingsView`.
- Credenciales Speediance solo en `backend/.env` (nunca commiteado, nunca en el iPhone). La app solo guarda la URL del backend y su API key.
- Tests iOS: contenedor SwiftData en memoria (`ModelConfiguration(isStoredInMemoryOnly: true)`), schema `[Workout.self, Exercise.self, WeightEntry.self, Meal.self, Recipe.self, PlannedMeal.self, ChatMessageRecord.self]`.
- Comando de tests iOS: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
- Backend: Python 3.11+, dependencias solo `fastapi`, `uvicorn`, `speediance`, `pytest`, `httpx`. Sin nuevas dependencias sin aprobar.

## Review Focus

1. **Cuenta en libras**: la librería devuelve pesos en la unidad de la cuenta; el backend debe convertir a kg (×0.45359237) o MyFit mostraría libras como kg. → test en Task 2.
2. **Sesión Free Lift sin detalle por serie**: llega con `exercises` vacío; debe importarse la sesión (fecha, duración, calorías) sin ejercicios, nunca descartarse. → tests en Task 2 y Task 5.
3. **Misma sesión ya importada por HealthKit con timestamp distinto**: debe enriquecerse el entreno existente (ventana de 15 min) en vez de duplicarse e inflar las estadísticas semanales. → test en Task 5.
4. **Backend apagado o inaccesible durante el sync automático**: el error se ignora en silencio y el sync de HealthKit continúa; la app no debe quedarse colgada. → estructura de Task 6 + verificación manual en Task 7.
5. **Fechas ISO8601 con y sin fracción de segundo** (`2026-09-18T07:30:00Z` vs `...T07:30:00.123Z`): el decoder de Swift debe aceptar ambas. → test en Task 4.

---

### Task 1: Backend — scaffold FastAPI con `/health`

**Files:**
- Create: `backend/requirements.txt`
- Create: `backend/.env.example`
- Create: `backend/app/__init__.py` (vacío)
- Create: `backend/app/config.py`
- Create: `backend/app/speediance_client.py`
- Create: `backend/app/main.py`
- Create: `backend/tests/__init__.py` (vacío)
- Create: `backend/tests/test_health.py`
- Modify: `.gitignore` (añadir `backend/.env` y `backend/.venv/`)

**Interfaces:**
- Consumes: nada (primer task).
- Produces: `Settings.from_env() -> Settings` con campos `email, password, region, api_key`; `check_speediance(settings) -> None` (lanza excepción si falla el login); `get_settings()` (dependencia FastAPI, sobreescribible en tests); app FastAPI en `app.main:app` con `GET /health`.

- [ ] **Step 1: Crear scaffold y test que falla**

`backend/requirements.txt`:
```
fastapi
uvicorn
speediance
pytest
httpx
```

`backend/.env.example`:
```
# Credenciales de tu cuenta Speediance (nunca commitear el .env real)
SPEEDIANCE_EMAIL=tu@email.com
SPEEDIANCE_PASSWORD=tu_password
# Region de la cuenta: EU o Global (las cuentas son específicas de región)
SPEEDIANCE_REGION=EU
# Secreto compartido que la app MyFit enviará en el header X-API-Key
BACKEND_API_KEY=genera-una-cadena-larga-y-aleatoria
```

`backend/app/config.py`:
```python
"""Configuración del backend desde variables de entorno / fichero .env."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

_ENV_PATH = Path(__file__).resolve().parent.parent / ".env"


def _load_dotenv() -> None:
    """Carga backend/.env si existe (sin dependencia externa)."""
    if not _ENV_PATH.exists():
        return
    for line in _ENV_PATH.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())


@dataclass(frozen=True)
class Settings:
    email: str
    password: str
    region: str  # "EU" | "Global"
    api_key: str

    @classmethod
    def from_env(cls) -> "Settings":
        _load_dotenv()
        missing = [k for k in ("SPEEDIANCE_EMAIL", "SPEEDIANCE_PASSWORD", "BACKEND_API_KEY")
                   if not os.environ.get(k)]
        if missing:
            raise RuntimeError(f"Faltan variables de entorno: {', '.join(missing)}")
        return cls(
            email=os.environ["SPEEDIANCE_EMAIL"],
            password=os.environ["SPEEDIANCE_PASSWORD"],
            region=os.environ.get("SPEEDIANCE_REGION", "EU"),
            api_key=os.environ["BACKEND_API_KEY"],
        )
```

`backend/app/speediance_client.py`:
```python
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
```

`backend/tests/test_health.py`:
```python
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
```

- [ ] **Step 2: Ejecutar el test y ver que falla**

Run: `cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt && .venv/bin/python -m pytest tests/test_health.py -v`
Expected: FAIL con `ModuleNotFoundError: No module named 'app.main'`

- [ ] **Step 3: Implementar `app/main.py`**

```python
"""API propia y estable del backend local de MyFit."""
from __future__ import annotations

from fastapi import Depends, FastAPI, Header, HTTPException

from .config import Settings
from .speediance_client import check_speediance

app = FastAPI(title="MyFit Backend")


def get_settings() -> Settings:
    return Settings.from_env()


def verify_api_key(
    x_api_key: str = Header(default=""),
    settings: Settings = Depends(get_settings),
) -> None:
    if not settings.api_key or x_api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="API key inválida")


@app.get("/health", dependencies=[Depends(verify_api_key)])
def health(settings: Settings = Depends(get_settings)) -> dict:
    try:
        check_speediance(settings)
        speediance = "connected"
    except Exception:
        speediance = "error"
    return {"status": "ok", "speediance": speediance}
```

- [ ] **Step 4: Ejecutar el test y ver que pasa**

Run: `cd backend && .venv/bin/python -m pytest tests/test_health.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
echo -e "backend/.env\nbackend/.venv/\nbackend/__pycache__/\nbackend/**/__pycache__/" >> .gitignore
git add backend/ .gitignore
git commit -m "feat(backend): scaffold FastAPI con /health y verificación de API key"
```

---

### Task 2: Backend — `GET /speediance/workouts` con mapeo y agregación

**Files:**
- Create: `backend/tests/test_workouts.py`
- Modify: `backend/app/speediance_client.py`
- Modify: `backend/app/main.py`

**Interfaces:**
- Consumes: Task 1 (`Settings`, `get_settings`, `verify_api_key`, app).
- Produces: `fetch_workouts(settings: Settings, since: date | None) -> list[dict]`; `session_to_dict(session: TrainingSession, unit: str) -> dict`. JSON de respuesta: `{"workouts": [{"id": str, "title": str, "date": "ISO8601 UTC con Z", "durationMinutes": int, "calories": int, "exercises": [{"name": str, "sets": int, "reps": int, "weightKg": float | None}]}]}`. **La app iOS (Task 4) decodifica exactamente este formato.**

Reglas de mapeo (del spec):
- `date` = `finished_at - duration_min` (inicio de la sesión, para casar con HealthKit); si `finished_at` es None, mediodía UTC del día.
- `reps` = media de reps por serie (redondeada); `weightKg` = `max_weight × load_points` (peso total movido, no por mango), convertido a kg si la cuenta es lb (×0.45359237); `weightKg` = None para ejercicios sin carga.
- Se incluyen todos los ejercicios con al menos una serie (también los sin peso); sesiones sin detalle devuelven `exercises: []`.

- [ ] **Step 1: Escribir los tests que fallan**

`backend/tests/test_workouts.py`:
```python
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
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `cd backend && .venv/bin/python -m pytest tests/test_workouts.py -v`
Expected: FAIL con `ImportError: cannot import name 'session_to_dict'`

- [ ] **Step 3: Implementar el mapeo en `speediance_client.py`**

Añadir al final de `backend/app/speediance_client.py`:

```python
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
        "durationMinutes": session.duration_min,
        "calories": session.calories,
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
```

- [ ] **Step 4: Implementar el endpoint en `main.py`**

Añadir a `backend/app/main.py` (imports al principio, endpoint al final):

```python
from datetime import date

from .speediance_client import check_speediance, fetch_workouts


@app.get("/speediance/workouts", dependencies=[Depends(verify_api_key)])
def speediance_workouts(
    since: date | None = None,
    settings: Settings = Depends(get_settings),
) -> dict:
    try:
        return {"workouts": fetch_workouts(settings, since)}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Error al leer Speediance: {exc}")
```

- [ ] **Step 5: Ejecutar y ver que pasa**

Run: `cd backend && .venv/bin/python -m pytest tests/ -v`
Expected: todos passed (11 tests)

- [ ] **Step 6: Commit**

```bash
git add backend/
git commit -m "feat(backend): GET /speediance/workouts con agregación por ejercicio"
```

---

### Task 3: iOS — campo `externalID` en `Workout`

**Files:**
- Modify: `MyFit/Models/Workout.swift:4-27`

**Interfaces:**
- Consumes: nada.
- Produces: `Workout.externalID: String?` e init ampliado `init(..., externalID: String? = nil)` — usado por Task 5. Los call sites existentes (`HealthKitService.toWorkout`, `WorkoutFormView`) no cambian porque el parámetro tiene default.

- [ ] **Step 1: Modificar el modelo**

En `MyFit/Models/Workout.swift`, dentro de `final class Workout`, añadir la propiedad tras `caloriesBurned`:

```swift
    var caloriesBurned: Int?
    /// ID de la sesión en el sistema de origen (p. ej. Speediance); nil en entrenos manuales o de HealthKit.
    var externalID: String?
```

Y ampliar el init:

```swift
    init(date: Date = Date(),
         type: WorkoutType = .strength,
         durationMinutes: Int = 60,
         notes: String = "",
         caloriesBurned: Int? = nil,
         externalID: String? = nil,
         exercises: [Exercise] = []) {
        self.date = date
        self.type = type
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.caloriesBurned = caloriesBurned
        self.externalID = externalID
        self.exercises = exercises
    }
```

- [ ] **Step 2: Regenerar proyecto y compilar + tests**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: build OK, todos los tests pasan (campo opcional → migración trivial de SwiftData).

- [ ] **Step 3: Commit**

```bash
git add MyFit/Models/Workout.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: añade externalID a Workout para deduplicación por origen"
```

---

### Task 4: iOS — `BackendService` (cliente HTTP + DTOs)

**Files:**
- Create: `MyFit/Services/BackendService.swift`
- Test: `MyFitTests/BackendServiceTests.swift`

**Interfaces:**
- Consumes: `KeychainHelper` (`read/save/delete(account:)`).
- Produces (los usa Task 5 y Task 6):
  - `BackendWorkoutDTO` / `BackendExerciseDTO` (Decodable, campos exactos del JSON de Task 2).
  - `protocol BackendServing: Sendable { func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO]; func checkHealth() async throws -> Bool }`
  - `struct BackendService: BackendServing` con `init(baseURL: URL, apiKey: String)` y `static func fromStoredConfiguration() -> BackendService?`
  - `BackendService.urlDefaultsKey = "backendBaseURL"`, `BackendService.apiKeyAccount = "myfit.backend.apikey"`
  - `enum BackendError: LocalizedError`

- [ ] **Step 1: Escribir el test que falla**

`MyFitTests/BackendServiceTests.swift`:
```swift
import Foundation
import Testing
@testable import MyFit

@Suite("BackendService · parsing del JSON del backend")
struct BackendServiceTests {

    private func decode(_ json: String) throws -> BackendWorkoutsResponse {
        try BackendService.makeDecoder().decode(BackendWorkoutsResponse.self,
                                                from: Data(json.utf8))
    }

    @Test("decodifica un entreno con ejercicios y peso")
    func decodesWorkout() throws {
        let response = try decode("""
        {"workouts": [{"id": "998877", "title": "Push Day",
                       "date": "2026-09-18T07:30:00Z",
                       "durationMinutes": 45, "calories": 320,
                       "exercises": [{"name": "Chest Press", "sets": 3, "reps": 10,
                                      "weightKg": 50.0}]}]}
        """)
        let workout = try #require(response.workouts.first)
        #expect(workout.id == "998877")
        #expect(workout.durationMinutes == 45)
        #expect(workout.exercises.first?.weightKg == 50.0)
    }

    @Test("acepta fechas con fracción de segundo y weightKg nulo")
    func decodesFractionalSecondsAndNullWeight() throws {
        let response = try decode("""
        {"workouts": [{"id": "1", "title": "Free Lift",
                       "date": "2026-09-18T07:30:00.123Z",
                       "durationMinutes": 30, "calories": 200,
                       "exercises": [{"name": "Stretch", "sets": 1, "reps": 1,
                                      "weightKg": null}]}]}
        """)
        #expect(response.workouts.first?.exercises.first?.weightKg == nil)
    }

    @Test("una sesión sin detalle llega con exercises vacío")
    func decodesSessionWithoutExercises() throws {
        let response = try decode("""
        {"workouts": [{"id": "2", "title": "Free Lift", "date": "2026-09-18T12:00:00Z",
                       "durationMinutes": 31, "calories": 260, "exercises": []}]}
        """)
        #expect(response.workouts.first?.exercises.isEmpty == true)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/BackendServiceTests`
Expected: FAIL de compilación (`cannot find 'BackendService'`)

- [ ] **Step 3: Implementar `BackendService.swift`**

```swift
import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "El backend no está configurado. Revisa Ajustes > Speediance."
        case .invalidResponse:
            return "La respuesta del backend no es válida."
        case .httpError(let status, let body):
            return "Error HTTP \(status) del backend: \(body.prefix(300))"
        }
    }
}

struct BackendExerciseDTO: Decodable, Sendable {
    let name: String
    let sets: Int
    let reps: Int
    let weightKg: Double?
}

struct BackendWorkoutDTO: Decodable, Sendable {
    let id: String
    let title: String
    let date: Date
    let durationMinutes: Int
    let calories: Int
    let exercises: [BackendExerciseDTO]
}

struct BackendWorkoutsResponse: Decodable, Sendable {
    let workouts: [BackendWorkoutDTO]
}

private struct BackendHealthResponse: Decodable {
    let status: String
    let speediance: String
}

protocol BackendServing: Sendable {
    /// Devuelve las sesiones desde `since` (nil = todo el historial).
    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO]
    /// true si el backend responde y además tiene login válido en Speediance.
    func checkHealth() async throws -> Bool
}

struct BackendService: BackendServing {
    static let urlDefaultsKey = "backendBaseURL"
    static let apiKeyAccount = "myfit.backend.apikey"

    let baseURL: URL
    let apiKey: String

    static func fromStoredConfiguration() -> BackendService? {
        guard let raw = UserDefaults.standard.string(forKey: urlDefaultsKey),
              let url = URL(string: raw),
              let key = KeychainHelper.read(account: apiKeyAccount),
              !key.isEmpty else { return nil }
        return BackendService(baseURL: url, apiKey: key)
    }

    /// Acepta ISO8601 con y sin fracción de segundo.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Fecha ISO8601 inválida: \(string)")
        }
        return decoder
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw BackendError.notConfigured }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw BackendError.notConfigured }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        return request
    }

    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO] {
        var queryItems: [URLQueryItem] = []
        if let since {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            queryItems = [URLQueryItem(name: "since", value: formatter.string(from: since))]
        }
        var request = try makeRequest(path: "speediance/workouts", queryItems: queryItems)
        // La primera importación recorre todo el historial a 1 petición/s: puede tardar minutos.
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpError(status: http.statusCode,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.makeDecoder().decode(BackendWorkoutsResponse.self, from: data).workouts
    }

    func checkHealth() async throws -> Bool {
        let request = try makeRequest(path: "health")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpError(status: http.statusCode,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        let health = try JSONDecoder().decode(BackendHealthResponse.self, from: data)
        return health.speediance == "connected"
    }
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/BackendServiceTests`
Expected: 3 tests passed

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/BackendService.swift MyFitTests/BackendServiceTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: BackendService, cliente HTTP del backend local (DTOs + health)"
```

---

### Task 5: iOS — `SpeedianceImporter` (deduplicación y enriquecimiento)

**Files:**
- Create: `MyFit/Services/SpeedianceImporter.swift`
- Test: `MyFitTests/SpeedianceImporterTests.swift`

**Interfaces:**
- Consumes: Task 3 (`Workout.externalID`), Task 4 (`BackendServing`, `BackendWorkoutDTO`, `BackendExerciseDTO`).
- Produces: `@MainActor struct SpeedianceImporter` con `init(backend: BackendServing)`, `@discardableResult func importWorkouts(context: ModelContext) async throws -> Int` (nº de entrenos NUEVOS insertados), `static let lastSyncKey = "sync.lastSpeediance"`. Usado por Task 6.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/SpeedianceImporterTests.swift`:
```swift
import Foundation
import SwiftData
import Testing
@testable import MyFit

/// Stub sin red: devuelve DTOs fijos.
private struct StubBackend: BackendServing {
    let workouts: [BackendWorkoutDTO]
    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO] { workouts }
    func checkHealth() async throws -> Bool { true }
}

@Suite("SpeedianceImporter · deduplicación y enriquecimiento")
@MainActor
struct SpeedianceImporterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeDTO(id: String, date: Date,
                         exercises: [BackendExerciseDTO] = []) -> BackendWorkoutDTO {
        BackendWorkoutDTO(id: id, title: "Sesión", date: date,
                          durationMinutes: 45, calories: 300, exercises: exercises)
    }

    private let benchPress = BackendExerciseDTO(name: "Bench Press", sets: 4, reps: 8,
                                                weightKg: 60.0)

    init() {
        UserDefaults.standard.removeObject(forKey: SpeedianceImporter.lastSyncKey)
    }

    @Test("importa un entreno nuevo con sus ejercicios y externalID")
    func importsNewWorkout() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-1", date: Date(), exercises: [benchPress])

        let imported = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(imported == 1)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let workout = try #require(workouts.first)
        #expect(workout.externalID == "spd-1")
        #expect(workout.type == .strength)
        #expect(workout.notes == "Importado de Speediance")
        #expect(workout.exercises.count == 1)
        #expect(workout.exercises.first?.weightKg == 60.0)
    }

    @Test("no duplica un externalID ya importado")
    func skipsExistingExternalID() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-1", date: Date(), exercises: [benchPress])
        let importer = SpeedianceImporter(backend: StubBackend(workouts: [dto]))

        _ = try await importer.importWorkouts(context: context)
        let second = try await importer.importWorkouts(context: context)

        #expect(second == 0)
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 1)
    }

    @Test("enriquece el entreno de HealthKit en la ventana de 15 min sin duplicar")
    func enrichesHealthKitMatch() async throws {
        let context = ModelContext(try makeContainer())
        let date = Date()
        context.insert(Workout(date: date, type: .strength, durationMinutes: 44,
                               notes: "Importado de Speediance", caloriesBurned: nil))
        let dto = makeDTO(id: "spd-9", date: date.addingTimeInterval(8 * 60),
                          exercises: [benchPress])

        let imported = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(imported == 0)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        #expect(workouts[0].externalID == "spd-9")
        #expect(workouts[0].caloriesBurned == 300)
        #expect(workouts[0].exercises.count == 1)
    }

    @Test("no fusiona entrenos a más de 15 minutos de distancia")
    func doesNotMergeDistantWorkouts() async throws {
        let context = ModelContext(try makeContainer())
        let date = Date()
        context.insert(Workout(date: date))
        let dto = makeDTO(id: "spd-10", date: date.addingTimeInterval(30 * 60))

        let imported = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(imported == 1)
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 2)
    }

    @Test("una sesión Free Lift sin detalle se importa sin ejercicios")
    func importsFreeLiftWithoutExercises() async throws {
        let context = ModelContext(try makeContainer())
        let dto = makeDTO(id: "spd-11", date: Date())

        let imported = try await SpeedianceImporter(backend: StubBackend(workouts: [dto]))
            .importWorkouts(context: context)

        #expect(imported == 1)
        let workout = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.exercises.isEmpty)
    }
}
```

- [ ] **Step 2: Ejecutar y ver que falla**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/SpeedianceImporterTests`
Expected: FAIL de compilación (`cannot find 'SpeedianceImporter'`)

- [ ] **Step 3: Implementar `SpeedianceImporter.swift`**

```swift
import Foundation
import SwiftData

/// Importa sesiones de Speediance (vía backend local) a SwiftData,
/// deduplicando contra entrenos ya existentes (HealthKit, manuales o importados antes).
@MainActor
struct SpeedianceImporter {
    static let lastSyncKey = "sync.lastSpeediance"
    /// Ventana para considerar que una sesión de Speediance y un entreno existente son el mismo.
    private static let matchWindow: TimeInterval = 15 * 60

    let backend: BackendServing

    /// Devuelve cuántos entrenos NUEVOS se insertaron (los enriquecidos no cuentan).
    @discardableResult
    func importWorkouts(context: ModelContext) async throws -> Int {
        let lastSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        let dtos = try await backend.fetchWorkouts(since: lastSync)
        let existing = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
        var imported = 0
        for dto in dtos {
            if existing.contains(where: { $0.externalID == dto.id }) { continue }
            if let match = existing.first(where: {
                abs($0.date.timeIntervalSince(dto.date)) < Self.matchWindow
            }) {
                // La misma sesión ya llegó por HealthKit o a mano: enriquecer, no duplicar.
                match.externalID = dto.id
                if match.caloriesBurned == nil { match.caloriesBurned = dto.calories }
                if match.exercises.isEmpty {
                    for exercise in dto.exercises {
                        match.exercises.append(Exercise(name: exercise.name,
                                                        sets: exercise.sets,
                                                        reps: exercise.reps,
                                                        weightKg: exercise.weightKg))
                    }
                }
                continue
            }
            context.insert(Self.makeWorkout(from: dto))
            imported += 1
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
        return imported
    }

    static func makeWorkout(from dto: BackendWorkoutDTO) -> Workout {
        Workout(date: dto.date,
                type: .strength,
                durationMinutes: max(1, dto.durationMinutes),
                notes: "Importado de Speediance",
                caloriesBurned: dto.calories,
                externalID: dto.id,
                exercises: dto.exercises.map {
                    Exercise(name: $0.name, sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg)
                })
    }
}
```

- [ ] **Step 4: Ejecutar y ver que pasa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/SpeedianceImporterTests`
Expected: 5 tests passed

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/SpeedianceImporter.swift MyFitTests/SpeedianceImporterTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: SpeedianceImporter con dedup por externalID y ventana de 15 min"
```

---

### Task 6: iOS — cableado (SyncService, Ajustes, importación manual)

**Files:**
- Modify: `MyFit/Services/SyncService.swift:13-23`
- Modify: `MyFit/Views/Settings/SettingsView.swift` (estado en líneas 5-31, sección nueva en el `Form`, helpers junto a `saveKey()` líneas 323-332 y `testConnection` líneas 260-289)
- Modify: `MyFit/Views/Workouts/WorkoutListView.swift:8-34,109-142`

**Interfaces:**
- Consumes: Task 4 (`BackendService.fromStoredConfiguration()`, `checkHealth()`, `urlDefaultsKey`, `apiKeyAccount`), Task 5 (`SpeedianceImporter`).
- Produces: sync automático al abrir la app; sección "Speediance" en Ajustes; menú "Importar de Speediance" en la lista de entrenos.

- [ ] **Step 1: SyncService — sync independiente de HealthKit**

En `MyFit/Services/SyncService.swift`, modificar `syncAll` para que el sync de Speediance no dependa de HealthKit, y añadir el método privado:

```swift
    func syncAll(context: ModelContext) async {
        await syncSpeediance(context: context)
        guard HealthKitService.isAvailable else { return }
        do {
            try await healthKit.requestAuthorization()
        } catch {
            return
        }
        await syncWorkouts(context: context)
        await syncWeight(context: context)
        await syncCalorieGoal()
    }

    /// Silencioso a propósito (patrón del sync automático): si el backend está
    /// apagado o no configurado, la app sigue funcionando igual que antes.
    private func syncSpeediance(context: ModelContext) async {
        guard let backend = BackendService.fromStoredConfiguration() else { return }
        do {
            try await SpeedianceImporter(backend: backend).importWorkouts(context: context)
        } catch {}
    }
```

- [ ] **Step 2: SettingsView — estado para la sección Speediance**

Junto a los `@AppStorage`/`@State` existentes (líneas 5-31), añadir:

```swift
    @AppStorage(BackendService.urlDefaultsKey) private var backendURL = "http://100.77.65.26:8000"
    @State private var backendAPIKeyInput = ""
    @State private var hasBackendAPIKey = false
    @State private var backendTestResult: String?
    @State private var isTestingBackend = false
```

- [ ] **Step 3: SettingsView — sección "Speediance" en el Form**

Añadir una sección nueva al `Form` (tras las secciones de proveedores de IA):

```swift
            Section {
                TextField("URL del backend", text: $backendURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API key del backend", text: $backendAPIKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Guardar") { saveBackendKey() }
                        .disabled(backendAPIKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasBackendAPIKey {
                        Button("Eliminar", role: .destructive) { deleteBackendKey() }
                    }
                }
                Button {
                    Task { await testBackendConnection() }
                } label: {
                    HStack {
                        Text("Probar conexión")
                        if isTestingBackend { ProgressView() }
                    }
                }
                .disabled(isTestingBackend)
                if let backendTestResult {
                    Text(backendTestResult)
                        .font(.footnote)
                        .foregroundStyle(backendTestResult.hasPrefix("✅") ? .green : .red)
                }
            } header: {
                Text("Speediance")
            } footer: {
                Text("URL del backend local que sincroniza tus entrenos de Speediance (funciona por Tailscale también fuera de casa).")
            }
```

- [ ] **Step 4: SettingsView — helpers**

Junto a `saveKey()`/`testConnection()`, añadir:

```swift
    private func saveBackendKey() {
        let key = backendAPIKeyInput.trimmingCharacters(in: .whitespaces)
        KeychainHelper.save(key, account: BackendService.apiKeyAccount)
        hasBackendAPIKey = true
        backendTestResult = nil
    }

    private func deleteBackendKey() {
        KeychainHelper.delete(account: BackendService.apiKeyAccount)
        backendAPIKeyInput = ""
        hasBackendAPIKey = false
        backendTestResult = nil
    }

    private func testBackendConnection() async {
        isTestingBackend = true
        defer { isTestingBackend = false }
        guard let backend = BackendService.fromStoredConfiguration() else {
            backendTestResult = "❌ Guarda primero la URL y la API key."
            return
        }
        do {
            backendTestResult = try await backend.checkHealth()
                ? "✅ Conexión OK y Speediance conectado"
                : "❌ El backend responde, pero el login de Speediance falla (revisa el .env del backend)"
        } catch {
            backendTestResult = "❌ \(error.localizedDescription)"
        }
    }
```

Y en el `.onAppear` existente (donde `loadKey()` precarga las claves), añadir la precarga:

```swift
        backendAPIKeyInput = KeychainHelper.read(account: BackendService.apiKeyAccount) ?? ""
        hasBackendAPIKey = !backendAPIKeyInput.isEmpty
```

- [ ] **Step 5: WorkoutListView — importación manual**

En `MyFit/Views/Workouts/WorkoutListView.swift`:

a) Estado (junto a líneas 10-11):

```swift
    @State private var isImportingSpeediance = false
    @State private var speedianceImportMessage: String?
```

b) Función (junto a `importFromHealth()`, líneas 15-34):

```swift
    private func importFromSpeediance() async {
        guard let backend = BackendService.fromStoredConfiguration() else {
            speedianceImportMessage = "Configura el backend en Ajustes > Speediance primero."
            return
        }
        isImportingSpeediance = true
        defer { isImportingSpeediance = false }
        do {
            let imported = try await SpeedianceImporter(backend: backend)
                .importWorkouts(context: context)
            speedianceImportMessage = imported == 0
                ? "No hay entrenamientos nuevos en Speediance."
                : "Se importaron \(imported) entrenamiento(s) desde Speediance."
        } catch {
            speedianceImportMessage = "Error al importar: \(error.localizedDescription)"
        }
    }
```

c) En el `Menu` del toolbar (línea 110), tras el botón "Importar de Salud":

```swift
                        if BackendService.fromStoredConfiguration() != nil {
                            Button {
                                Task { @MainActor in await importFromSpeediance() }
                            } label: {
                                Label("Importar de Speediance", systemImage: "dumbbell")
                            }
                            .disabled(isImportingSpeediance)
                        }
```

Y en el spinner del menú (línea 128), cambiar la condición a `if isImportingHealth || isImportingSpeediance {`.

d) Tras el `.alert("Importar de Salud", ...)` (líneas 136-142), añadir:

```swift
            .alert("Importar de Speediance",
                   isPresented: Binding(get: { speedianceImportMessage != nil },
                                        set: { if !$0 { speedianceImportMessage = nil } })) {
                Button("OK") { speedianceImportMessage = nil }
            } message: {
                Text(speedianceImportMessage ?? "")
            }
```

- [ ] **Step 6: Compilar y ejecutar toda la suite**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
Expected: build OK, toda la suite passed

- [ ] **Step 7: Commit**

```bash
git add MyFit/ MyFit.xcodeproj/project.pbxproj
git commit -m "feat: sync automático Speediance, sección en Ajustes e importación manual"
```

---

### Task 7: Documentación del backend y verificación E2E

**Files:**
- Create: `backend/README.md`

**Interfaces:**
- Consumes: todo lo anterior.

- [ ] **Step 1: Escribir `backend/README.md`**

```markdown
# MyFit Backend

Backend local que expone los entrenos de Speediance a la app MyFit.
Usa la librería no oficial `speediance` (la API de Speediance puede cambiar
sin aviso; si algo se rompe, suele bastar `pip install -U speediance`).

## Arranque

    cd backend
    python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
    cp .env.example .env   # rellena credenciales Speediance y BACKEND_API_KEY
    .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

La app MyFit se conecta a `http://100.77.65.26:8000` (Tailscale) con la
misma API key en Ajustes > Speediance.

## Endpoints

- `GET /health` — estado del backend y del login de Speediance.
- `GET /speediance/workouts?since=YYYY-MM-DD` — sesiones con ejercicios
  agregados. Sin `since`, todo el historial (puede tardar minutos: la API
  de Speediance se recorre a 1 petición/segundo).

Ambos requieren el header `X-API-Key`.

## Tests

    .venv/bin/python -m pytest tests/ -v
```

- [ ] **Step 2: Verificación E2E manual (con el usuario)**

1. Rellenar `backend/.env` con las credenciales reales de Speediance.
2. Arrancar: `cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000`
3. `curl -H "X-API-Key: <key>" http://100.77.65.26:8000/health` → `{"status":"ok","speediance":"connected"}`
4. `curl -H "X-API-Key: <key>" "http://100.77.65.26:8000/speediance/workouts?since=<hace 7 días>"` → JSON con sesiones reales; **comparar 2-3 ejercicios contra la app oficial de Speediance** (series, reps y peso — validar el criterio por mango vs total pendiente del spec).
5. En la app: Ajustes > Speediance → guardar API key → "Probar conexión" → ✅.
6. Menú de Entrenamientos → "Importar de Speediance" → verificar que los entrenos aparecen con ejercicios y **que no hay duplicados** de los que ya vinieron por HealthKit.
7. Con el backend apagado, abrir la app → debe abrir normal y sincronizar HealthKit sin errores visibles (Review Focus #4).

- [ ] **Step 3: Commit final**

```bash
git add backend/README.md
git commit -m "docs(backend): README con arranque, endpoints y tests"
```
