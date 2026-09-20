# Integración Cookidoo / Thermomix — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrar Cookidoo en MyFit (buscar/importar recetas, recomendar por macros en el chat, planificar en la TM6 y lista de la compra) sobre el backend local FastAPI existente.

**Architecture:** Backend "tonto" (router `/cookidoo` proxy puro sobre la librería no oficial `cookidoo-api`, OAuth gestionado por la librería con email/password del `.env`); toda la inteligencia en la app (recomendación vía el proveedor de IA ya configurado, reutilizando la fontanería y config de `BackendService`).

**Tech Stack:** Python 3.11+, FastAPI, `cookidoo-api` (aiohttp), pytest · iOS 17, Swift 6, SwiftUI, SwiftData, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-20-cookidoo-thermomix-design.md`

## Global Constraints

- **Dependencia de otro trabajo en curso**: el backend de Speediance (`backend/app/main.py`) y `BackendService.swift` están siendo implementados por otro agente según `docs/superpowers/plans/2026-09-20-speediance-import.md`. Las Tasks 1-3 (backend) requieren que `main.py` exista con `app` y `get_settings` (contrato visible en `backend/tests/test_health.py`). Las Tasks 4-9 (app) requieren `BackendService` con `BackendService.urlDefaultsKey = "backendBaseURL"` y `BackendService.apiKeyAccount = "myfit.backend.apikey"`. Si aún no están, ejecutar primero ese plan.
- El router Cookidoo toca `main.py` en **una sola línea** (`include_router`); todo lo demás vive en ficheros nuevos para no pisar al otro agente.
- Comando de tests iOS: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet` (con `-only-testing:MyFitTests/<Suite>` para suites concretas). Tras crear ficheros nuevos: `xcodegen generate` primero (fuentes por glob, no hay que editar el pbxproj).
- Comando de tests backend: `cd backend && .venv/bin/pytest -v` (o `pytest` con el venv activado).
- Mensajes de error de la app en español (patrón `AIServiceError`/`BackendError`).
- Credenciales Cookidoo solo en `backend/.env` (`COOKIDOO_EMAIL`, `COOKIDOO_PASSWORD`); token en `backend/.cookidoo-token.json` (nunca commiteado). La API key del backend viaja en header `X-API-Key`.
- La app nunca habla con Cookidoo directamente; solo con el backend propio.
- Pasos de receta: Cookidoo devuelve HTML; el backend lo convierte a texto plano antes de servirlo.

## Review Focus

1. **Receta sin nutrición en Cookidoo** (`nutrition_groups` vacío) → el detalle debe servir `"nutrition": null` y la app estimar macros por IA marcándolos como estimados (tests en Task 1 y Task 6).
2. **HTML raro en los pasos** (tags anidados, entidades `&amp;`, `<br>`) → el stripper del backend debe devolver texto legible, nunca HTML crudo (test en Task 1).
3. **Búsqueda sin resultados** → `{"recipes": [], "total": 0}` y la app muestra estado vacío, no un error (tests en Task 2 y Task 8).
4. **Credenciales Cookidoo caducadas** → el backend re-loguea solo; si ya no valen, `401 {"error": "reauth_required"}` y la app muestra "actualiza el .env del backend" (tests en Task 2 y Task 5).
5. **Importar dos veces la misma receta** → dedup por `cookidooId`: se devuelve la receta existente, no se duplica (test en Task 6).

---

## Fase 1 — Backend (requiere `main.py` de Speediance)

### Task 1: Cliente Cookidoo (`cookidoo_client.py`)

**Files:**
- Create: `backend/app/cookidoo_client.py`
- Modify: `backend/app/config.py` (añadir campos `cookidoo_email`, `cookidoo_password`)
- Modify: `backend/requirements.txt` (añadir `cookidoo-api`)
- Modify: `backend/.env.example` (documentar las nuevas variables)
- Modify: `.gitignore` (añadir `backend/.cookidoo-token.json`)
- Test: `backend/tests/test_cookidoo_client.py`

**Interfaces:**
- Consumes: `Settings` de `app.config`; la librería `cookidoo_api` (`Cookidoo`, `CookidooConfig`, `CookidooLocalizationConfig`).
- Produces (lo usa Task 2):
  - `async def search_recipes(settings: Settings, query: str, page: int = 0) -> dict` → `{"recipes": [{"id", "title", "imageURL", "url"}], "total": int}`
  - `async def recipe_details(settings: Settings, recipe_id: str) -> dict` → `{"id", "title", "imageURL", "url", "totalMinutes", "difficulty", "servings", "ingredientSections": [{"title", "items": [str]}], "stepSections": [...], "nutrition": {"calories", "proteinGrams", "carbsGrams", "fatGrams"} | None}`
  - `async def calendar_week(settings: Settings, day: date) -> dict` → `{"days": [{"date": "2026-09-22", "recipes": [{"id", "title", "totalMinutes"}]}]}`
  - `async def add_recipe_to_calendar(settings: Settings, recipe_id: str, day: date) -> None`
  - `async def add_recipe_to_shopping_list(settings: Settings, recipe_id: str) -> int` (nº de ingredientes añadidos)
  - `class CookidooReauthRequired(Exception)` — se lanza cuando login y refresh fallan; el router la traduce a `401 reauth_required`.
  - `def strip_html(text: str) -> str` — pura, testeable aparte.
  - `def map_nutrition(groups) -> dict | None` — pura, testeable aparte.

- [ ] **Step 1: Actualizar dependencias y config**

`backend/requirements.txt` — añadir las líneas:
```
cookidoo-api
pytest-asyncio
```

`backend/.env.example` — añadir al final:
```
# Credenciales de tu cuenta Cookidoo (nunca commitear el .env real)
COOKIDOO_EMAIL=tu@email.com
COOKIDOO_PASSWORD=tu_password
```

`.gitignore` — añadir la línea:
```
backend/.cookidoo-token.json
```

`backend/app/config.py` — añadir los campos al dataclass `Settings` y a `from_env` (las credenciales Cookidoo son opcionales: el backend arranca sin ellas y solo fallan los endpoints `/cookidoo`):

```python
@dataclass(frozen=True)
class Settings:
    email: str
    password: str
    region: str  # "EU" | "Global"
    api_key: str
    cookidoo_email: str = ""
    cookidoo_password: str = ""

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
            cookidoo_email=os.environ.get("COOKIDOO_EMAIL", ""),
            cookidoo_password=os.environ.get("COOKIDOO_PASSWORD", ""),
        )
```

Ojo: los tests existentes construyen `Settings(email=..., password=..., region=..., api_key=...)` posicionalmente — los nuevos campos llevan default para no romperlos.

- [ ] **Step 2: Escribir los tests que fallan**

`backend/tests/test_cookidoo_client.py`:

```python
from datetime import date
from types import SimpleNamespace

import pytest

from app.config import Settings
from app import cookidoo_client

TEST_SETTINGS = Settings(email="t@example.com", password="pw", region="EU", api_key="secret",
                         cookidoo_email="c@example.com", cookidoo_password="pw")


def test_strip_html_basico():
    assert cookidoo_client.strip_html("<p>Ponga el <b>agua</b> en el vaso.</p>") == "Ponga el agua en el vaso."


def test_strip_html_entidades_y_br():
    assert cookidoo_client.strip_html("Sal &amp; pimienta<br>Mezclar 5 seg./vel. 4") == "Sal & pimienta\nMezclar 5 seg./vel. 4"


def test_map_nutrition_por_racion():
    groups = [SimpleNamespace(recipe_nutritions=[SimpleNamespace(quantity=1, unit_notation="ración", nutritions=[
        SimpleNamespace(number=320.0, type="kcal", unittype="kcal"),
        SimpleNamespace(number=28.0, type="protein", unittype="g"),
        SimpleNamespace(number=6.0, type="carbohydrates", unittype="g"),
        SimpleNamespace(number=18.0, type="fat", unittype="g"),
    ])])]
    assert cookidoo_client.map_nutrition(groups) == {
        "calories": 320, "proteinGrams": 28.0, "carbsGrams": 6.0, "fatGrams": 18.0,
    }


def test_map_nutrition_convierte_kj_a_kcal():
    groups = [SimpleNamespace(recipe_nutritions=[SimpleNamespace(quantity=1, unit_notation="ración", nutritions=[
        SimpleNamespace(number=1339.0, type="energy", unittype="kJ"),
    ])])]
    result = cookidoo_client.map_nutrition(groups)
    assert result["calories"] == 320  # 1339 / 4.184 ≈ 320


def test_map_nutrition_vacio_devuelve_none():
    assert cookidoo_client.map_nutrition([]) is None


@pytest.mark.asyncio
async def test_search_recipes_mapea_a_json_propio(monkeypatch):
    hit = SimpleNamespace(id="r90756", name="Salmón al vapor", thumbnail=None,
                          image="https://img/r90756.jpg", url="https://cookidoo.es/recipes/recipe/es-ES/r90756")

    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path): pass
        async def login(self): pass
        async def search_recipes(self, query, page=None, **kw):
            return SimpleNamespace(recipes=[hit], total=1)

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    result = await cookidoo_client.search_recipes(TEST_SETTINGS, "salmón")
    assert result["total"] == 1
    assert result["recipes"] == [{
        "id": "r90756", "title": "Salmón al vapor",
        "imageURL": "https://img/r90756.jpg",
        "url": "https://cookidoo.es/recipes/recipe/es-ES/r90756",
    }]


@pytest.mark.asyncio
async def test_login_fallido_lanza_reauth(monkeypatch):
    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path): pass
        async def login(self): raise Exception("invalid credentials")

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    with pytest.raises(cookidoo_client.CookidooReauthRequired):
        await cookidoo_client.search_recipes(TEST_SETTINGS, "salmón")
```

Nota para el implementador: los tests usan `SimpleNamespace` para simular los dataclasses de la librería; el mapeo debe leer atributos (no claves). Si la librería instalada usa nombres de atributo distintos a los de `types.py` de la versión documentada (verificado en `cookidoo_api/types.py`: `CookidooSearchRecipeHit(id, name, thumbnail, image, url)`, `CookidooShoppingRecipeDetails(... difficulty, serving_size, active_time, total_time, nutrition_groups, step_groups)`, `CookidooRecipeStepGroup(title, recipe_steps)`, `CookidooRecipeStep(title, formatted_text)`, `CookidooIngredient(id, name, description)`), ajustar el mapeo a los nombres reales y actualizar estos tests.

- [ ] **Step 3: Ejecutar y verlos fallar**

Run: `cd backend && .venv/bin/pytest tests/test_cookidoo_client.py -v`
Expected: FAIL (`ModuleNotFoundError: app.cookidoo_client` o similar).

- [ ] **Step 4: Implementar `backend/app/cookidoo_client.py`**

```python
"""Acceso a Cookidoo a través de la librería no oficial `cookidoo-api`.

La librería resuelve el flujo OAuth2 (authorization-code + PKCE, cliente público
de la app móvil) a partir del email/password del .env. El token se persiste en
backend/.cookidoo-token.json y la librería lo refresca sola; el callback
`on_auth_data_update` mantiene el fichero en sync tras cada login/refresh.
"""
from __future__ import annotations

import html
import re
from datetime import date
from pathlib import Path

import aiohttp
# Import a nivel de módulo con alias: los tests lo sustituyen con
# monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo), y eso solo
# funciona si `_Cookidoo` es un atributo del módulo (no un import local).
from cookidoo_api import Cookidoo as _Cookidoo
from cookidoo_api.types import CookidooConfig, CookidooLocalizationConfig

from .config import Settings

_TOKEN_PATH = Path(__file__).resolve().parent.parent / ".cookidoo-token.json"


class CookidooReauthRequired(Exception):
    """Las credenciales del .env ya no valen: hay que actualizarlas."""


def strip_html(text: str) -> str:
    """Convierte el HTML de los pasos de Cookidoo a texto plano legible."""
    text = re.sub(r"<br\s*/?>", "\n", text)
    text = re.sub(r"</p>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text).strip()


def map_nutrition(groups) -> dict | None:
    """Extrae kcal/proteína/carbos/grasa por ración de los nutrition_groups.

    Devuelve None si Cookidoo no expone nutrición para la receta (la app
    estimará los macros por IA en ese caso).
    """
    if not groups:
        return None
    recipe_nutritions = getattr(groups[0], "recipe_nutritions", [])
    if not recipe_nutritions:
        return None
    nutritions = getattr(recipe_nutritions[0], "nutritions", [])
    result: dict = {}
    for n in nutritions:
        kind = (getattr(n, "type", "") or "").lower()
        unit = (getattr(n, "unittype", "") or "").lower()
        number = float(getattr(n, "number", 0) or 0)
        if "cal" in kind or "energ" in kind:
            result["calories"] = round(number / 4.184) if unit == "kj" else round(number)
        elif "prote" in kind:
            result["proteinGrams"] = number
        elif "carb" in kind or "hidrat" in kind:
            result["carbsGrams"] = number
        elif "fat" in kind or "grasa" in kind:
            result["fatGrams"] = number
    return result or None


async def _with_client(settings: Settings, fn):
    """Crea sesión aiohttp + cliente Cookidoo, loguea y ejecuta fn(client)."""
    if not settings.cookidoo_email or not settings.cookidoo_password:
        raise CookidooReauthRequired("Faltan COOKIDOO_EMAIL/COOKIDOO_PASSWORD en el .env")

    jar = aiohttp.CookieJar(unsafe=True)  # el flujo de login usa cookies cross-domain
    async with aiohttp.ClientSession(cookie_jar=jar) as session:
        client = _Cookidoo(session, cfg=CookidooConfig(
            email=settings.cookidoo_email,
            password=settings.cookidoo_password,
            localization=CookidooLocalizationConfig(
                country_code="es", language="es-ES",
                url="https://cookidoo.es/foundation/es-ES"),
        ))
        client.on_auth_data_update = lambda _auth: client.save_token(str(_TOKEN_PATH))
        try:
            client.load_token(str(_TOKEN_PATH))
        except Exception:
            try:
                await client.login()
            except Exception as exc:
                raise CookidooReauthRequired(str(exc)) from exc
        return await fn(client)


async def search_recipes(settings: Settings, query: str, page: int = 0) -> dict:
    async def run(client):
        return await client.search_recipes(query, page=page)
    result = await _with_client(settings, run)
    return {
        "recipes": [
            {"id": r.id, "title": r.name, "imageURL": r.image, "url": r.url}
            for r in result.recipes
        ],
        "total": result.total,
    }


async def recipe_details(settings: Settings, recipe_id: str) -> dict:
    async def run(client):
        return await client.get_recipe_details(recipe_id)
    d = await _with_client(settings, run)
    return {
        "id": d.id,
        "title": d.name,
        "imageURL": d.image,
        "url": d.url,
        "totalMinutes": round(d.total_time / 60) if d.total_time else None,
        "difficulty": d.difficulty or None,
        "servings": d.serving_size or None,
        "ingredientSections": [
            {"title": None, "items": [i.description or i.name for i in d.ingredients]}
        ],
        "stepSections": [
            {"title": g.title or None,
             "items": [strip_html(s.formatted_text) for s in g.recipe_steps]}
            for g in d.step_groups
        ],
        "nutrition": map_nutrition(d.nutrition_groups),
    }


async def calendar_week(settings: Settings, day: date) -> dict:
    async def run(client):
        return await client.get_recipes_in_calendar_week(day)
    days = await _with_client(settings, run)
    return {
        "days": [
            {"date": d.title,  # la librería pone la fecha ISO en `title`
             "recipes": [{"id": r.id, "title": r.name,
                          "totalMinutes": round(r.total_time / 60)} for r in d.recipes]}
            for d in days
        ]
    }


async def add_recipe_to_calendar(settings: Settings, recipe_id: str, day: date) -> None:
    async def run(client):
        await client.add_recipes_to_calendar(day, [recipe_id])
    await _with_client(settings, run)


async def add_recipe_to_shopping_list(settings: Settings, recipe_id: str) -> int:
    async def run(client):
        return await client.add_ingredient_items_for_recipes([recipe_id])
    items = await _with_client(settings, run)
    return len(items)
```

- [ ] **Step 5: Ejecutar y verlos pasar**

Run: `cd backend && .venv/bin/pytest tests/test_cookidoo_client.py -v`
Expected: PASS (todos).

- [ ] **Step 6: Commit**

```bash
git add backend/app/cookidoo_client.py backend/app/config.py backend/requirements.txt backend/.env.example .gitignore backend/tests/test_cookidoo_client.py
git commit -m "feat(backend): cliente Cookidoo (búsqueda, detalle, planner, lista de la compra)"
```

### Task 2: Router HTTP `/cookidoo`

**Files:**
- Create: `backend/app/cookidoo_router.py`
- Modify: `backend/app/main.py` (una línea: `app.include_router(...)`)
- Test: `backend/tests/test_cookidoo_router.py`

**Interfaces:**
- Consumes: `cookidoo_client` (Task 1) y `get_settings` de `app.main`.
- Produces (los consume Task 5 de la app):
  - `GET /cookidoo/recipes/search?q=...&page=0` → JSON de `search_recipes`
  - `GET /cookidoo/recipes/{recipe_id}` → JSON de `recipe_details`
  - `GET /cookidoo/planner/week?date=YYYY-MM-DD` → JSON de `calendar_week`
  - `POST /cookidoo/planner/add` body `{"recipeId": "r90756", "date": "2026-09-22"}` → `{"ok": true}`
  - `POST /cookidoo/shopping-list/add-recipe` body `{"recipeId": "r90756"}` → `{"ok": true, "ingredientsAdded": 12}`
  - Todos exigen header `X-API-Key`; `CookidooReauthRequired` → `401 {"error": "reauth_required"}`; receta inexistente o error upstream → `502 {"error": "cookidoo_error", "detail": ...}`.

- [ ] **Step 1: Escribir los tests que fallan**

`backend/tests/test_cookidoo_router.py`:

```python
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import app, get_settings
from app import cookidoo_router

TEST_SETTINGS = Settings(email="t@example.com", password="pw", region="EU", api_key="secret",
                         cookidoo_email="c@example.com", cookidoo_password="pw")


@pytest.fixture
def client(monkeypatch):
    app.dependency_overrides[get_settings] = lambda: TEST_SETTINGS
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_search_ok(client, monkeypatch):
    async def fake(settings, query, page=0):
        return {"recipes": [{"id": "r1", "title": "Salmón", "imageURL": None, "url": "u"}], "total": 1}
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "search_recipes", fake)
    r = client.get("/cookidoo/recipes/search?q=salmón", headers={"X-API-Key": "secret"})
    assert r.status_code == 200
    assert r.json()["total"] == 1


def test_search_vacia(client, monkeypatch):
    async def fake(settings, query, page=0):
        return {"recipes": [], "total": 0}
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "search_recipes", fake)
    r = client.get("/cookidoo/recipes/search?q=xyz", headers={"X-API-Key": "secret"})
    assert r.status_code == 200
    assert r.json() == {"recipes": [], "total": 0}


def test_reauth_required_mapea_a_401(client, monkeypatch):
    async def fake(settings, query, page=0):
        raise cookidoo_router.cookidoo_client.CookidooReauthRequired("bad creds")
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "search_recipes", fake)
    r = client.get("/cookidoo/recipes/search?q=x", headers={"X-API-Key": "secret"})
    assert r.status_code == 401
    assert r.json() == {"error": "reauth_required"}


def test_planner_add_ok(client, monkeypatch):
    llamadas = {}

    async def fake(settings, recipe_id, day):
        llamadas["args"] = (recipe_id, day)
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "add_recipe_to_calendar", fake)
    r = client.post("/cookidoo/planner/add",
                    json={"recipeId": "r90756", "date": "2026-09-22"},
                    headers={"X-API-Key": "secret"})
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    assert llamadas["args"][0] == "r90756"


def test_shopping_list_devuelve_conteo(client, monkeypatch):
    async def fake(settings, recipe_id):
        return 12
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "add_recipe_to_shopping_list", fake)
    r = client.post("/cookidoo/shopping-list/add-recipe",
                    json={"recipeId": "r90756"}, headers={"X-API-Key": "secret"})
    assert r.status_code == 200
    assert r.json() == {"ok": True, "ingredientsAdded": 12}


def test_rechaza_sin_api_key(client):
    assert client.get("/cookidoo/recipes/search?q=x").status_code == 401
```

- [ ] **Step 2: Ejecutar y verlos fallar**

Run: `cd backend && .venv/bin/pytest tests/test_cookidoo_router.py -v`
Expected: FAIL (`ModuleNotFoundError: app.cookidoo_router`).

- [ ] **Step 3: Implementar `backend/app/cookidoo_router.py`**

```python
"""Router /cookidoo: proxy puro de cookidoo_client con auth X-API-Key propia.

Define su propia dependencia de API key para no acoplarse a los internals de
main.py (que pertenece al trabajo de Speediance); solo necesita `get_settings`.
"""
from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from .config import Settings
from . import cookidoo_client
from .main import get_settings  # la dependencia de settings la define main

router = APIRouter(prefix="/cookidoo", tags=["cookidoo"])


def require_api_key(
    x_api_key: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> None:
    if x_api_key != settings.api_key:
        raise HTTPException(status_code=401, detail="invalid api key")


def _reauth_response() -> JSONResponse:
    """401 con cuerpo plano {"error": "reauth_required"} (HTTPException envolvería
    el dict en "detail", y la app espera el cuerpo plano)."""
    return JSONResponse(status_code=401, content={"error": "reauth_required"})


def _upstream_error(exc: Exception) -> HTTPException:
    return HTTPException(status_code=502,
                         detail={"error": "cookidoo_error", "detail": str(exc)})


class PlannerAddBody(BaseModel):
    recipeId: str
    date: date


class ShoppingAddBody(BaseModel):
    recipeId: str


@router.get("/recipes/search", dependencies=[Depends(require_api_key)])
async def search(q: str, page: int = 0, settings: Settings = Depends(get_settings)):
    try:
        return await cookidoo_client.search_recipes(settings, q, page=page)
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        raise _upstream_error(exc) from exc


@router.get("/recipes/{recipe_id}", dependencies=[Depends(require_api_key)])
async def details(recipe_id: str, settings: Settings = Depends(get_settings)):
    try:
        return await cookidoo_client.recipe_details(settings, recipe_id)
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        raise _upstream_error(exc) from exc


@router.get("/planner/week", dependencies=[Depends(require_api_key)])
async def week(date: date, settings: Settings = Depends(get_settings)):
    try:
        return await cookidoo_client.calendar_week(settings, date)
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        raise _upstream_error(exc) from exc


@router.post("/planner/add", dependencies=[Depends(require_api_key)])
async def planner_add(body: PlannerAddBody, settings: Settings = Depends(get_settings)):
    try:
        await cookidoo_client.add_recipe_to_calendar(settings, body.recipeId, body.date)
        return {"ok": True}
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        raise _upstream_error(exc) from exc


@router.post("/shopping-list/add-recipe", dependencies=[Depends(require_api_key)])
async def shopping_add(body: ShoppingAddBody, settings: Settings = Depends(get_settings)):
    try:
        n = await cookidoo_client.add_recipe_to_shopping_list(settings, body.recipeId)
        return {"ok": True, "ingredientsAdded": n}
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        raise _upstream_error(exc) from exc
```

En `backend/app/main.py`, registrar el router junto al resto de la configuración de `app`:

```python
from .cookidoo_router import router as cookidoo_router
app.include_router(cookidoo_router)
```

(El estilo exacto de import —`from .` vs `from app`— debe seguir el que use `main.py` cuando exista.)

- [ ] **Step 4: Ejecutar y verlos pasar**

Run: `cd backend && .venv/bin/pytest tests/test_cookidoo_router.py -v`
Expected: PASS (todos).

- [ ] **Step 5: Commit**

```bash
git add backend/app/cookidoo_router.py backend/app/main.py backend/tests/test_cookidoo_router.py
git commit -m "feat(backend): router /cookidoo (search, detalle, planner, lista de la compra)"
```

### Task 3: Health con estado Cookidoo + README del backend

**Files:**
- Modify: `backend/app/main.py` (handler de `/health`)
- Create: `backend/README.md`
- Test: `backend/tests/test_health.py` (extender)

**Interfaces:**
- Consumes: `cookidoo_client.search_recipes` no — usa un chequeo barato propio (ver abajo).
- Produces: `GET /health` → `{"status": "ok", "speediance": "connected"|"error", "cookidoo": "connected"|"error"|"reauth_required"|"not_configured"}`. Lo consume Task 9 de la app.

- [ ] **Step 1: Extender el test de health**

Añadir a `backend/tests/test_health.py`:

```python
def test_health_incluye_estado_cookidoo(client, monkeypatch):
    from app import main
    monkeypatch.setattr(main, "check_cookidoo", lambda settings: "connected")
    response = client.get("/health", headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    assert response.json()["cookidoo"] == "connected"
```

Y **actualizar los tests existentes** `test_health_ok` y `test_health_speediance_error`, que hoy comparan el JSON completo: con el campo nuevo pasan a incluir `"cookidoo"`. Como el `TEST_SETTINGS` del fichero no lleva credenciales Cookidoo, el estado será `"not_configured"`:

```python
def test_health_ok(client):
    response = client.get("/health", headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "speediance": "connected", "cookidoo": "not_configured"}


def test_health_speediance_error(client, monkeypatch):
    def boom(settings):
        raise RuntimeError("login failed")

    monkeypatch.setattr("app.main.check_speediance", boom)
    response = client.get("/health", headers={"X-API-Key": "secret"})
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "speediance": "error", "cookidoo": "not_configured"}
```

- [ ] **Step 2: Ejecutar y verlos fallar**

Run: `cd backend && .venv/bin/pytest tests/test_health.py -v`
Expected: FAIL (la clave `cookidoo` no existe / `check_cookidoo` no existe).

- [ ] **Step 3: Implementar `check_cookidoo` en `main.py` y ampliar `/health`**

Chequeo barato: sin llamar a Cookidoo en cada health, basta comprobar configuración + que el token existe o se puede loguear. Para no pegar a la API real en cada "Probar conexión"... no: el botón de la app es manual y poco frecuente, así que sí hacemos un chequeo real ligero (`get_user_info`):

```python
def check_cookidoo(settings: Settings) -> str:
    """Estado de Cookidoo para /health. Síncrono de cara al handler async."""
    if not settings.cookidoo_email:
        return "not_configured"
    import asyncio
    from . import cookidoo_client

    async def probe() -> str:
        try:
            await cookidoo_client._with_client(settings, lambda c: c.get_user_info())
            return "connected"
        except cookidoo_client.CookidooReauthRequired:
            return "reauth_required"
        except Exception:
            return "error"

    return asyncio.run(probe())
```

Y en el handler de `/health` (donde ya se llama a `check_speediance`):

```python
    return {
        "status": "ok",
        "speediance": speediance_status,
        "cookidoo": await asyncio.to_thread(check_cookidoo, settings),
    }
```

(Adaptar a la estructura real del handler que deje el trabajo de Speediance; si el handler es síncrono, llamar directamente.)

- [ ] **Step 4: Escribir `backend/README.md`**

```markdown
# Backend local de MyFit

Backend mono-usuario (FastAPI) que aisla a la app de las APIs no oficiales de Speediance y Cookidoo.

## Setup

    python3.11 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    cp .env.example .env   # rellena credenciales y BACKEND_API_KEY

## Arranque

    .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

La app se configura con `http://100.77.65.26:8000` (Tailscale) y la API key en el header `X-API-Key`.

## Tests

    .venv/bin/pytest -v

## Cookidoo

El login OAuth lo hace la librería con `COOKIDOO_EMAIL`/`COOKIDOO_PASSWORD` del `.env`. El token se guarda en `.cookidoo-token.json` (no commiteado) y se refresca solo. Si los endpoints devuelven `reauth_required`, actualiza las credenciales del `.env` y borra `.cookidoo-token.json`.
```

- [ ] **Step 5: Ejecutar todos los tests del backend**

Run: `cd backend && .venv/bin/pytest -v`
Expected: PASS (health + client + router).

- [ ] **Step 6: Commit**

```bash
git add backend/app/main.py backend/README.md backend/tests/test_health.py
git commit -m "feat(backend): estado de Cookidoo en /health y README de arranque"
```

---

## Fase 2 — App (requiere `BackendService` del plan de Speediance)

### Task 4: Campos `cookidooId` e `imageURL` en `Recipe`

**Files:**
- Modify: `MyFit/Models/Recipe.swift`
- Test: `MyFitTests/RecipeCookidooTests.swift`

**Interfaces:**
- Consumes: nada nuevo.
- Produces (lo usan Tasks 6, 7 y 8): `Recipe.cookidooId: String?`, `Recipe.imageURL: String?`, ambos con default `nil` en el `init`.

- [ ] **Step 1: Escribir el test que falla**

`MyFitTests/RecipeCookidooTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("Recipe · campos Cookidoo")
struct RecipeCookidooTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test("cookidooId e imageURL sobreviven al guardado")
    func cookidooFieldsRoundTrip() throws {
        let container = try makeContainer()
        let writing = ModelContext(container)
        writing.insert(Recipe(name: "Salmón al vapor", source: "cookidoo",
                              cookidooId: "r90756",
                              imageURL: "https://img/r90756.jpg"))
        try writing.save()

        let reading = ModelContext(container)
        let restored = try #require(try reading.fetch(FetchDescriptor<Recipe>()).first)
        #expect(restored.cookidooId == "r90756")
        #expect(restored.imageURL == "https://img/r90756.jpg")
        #expect(restored.source == "cookidoo")
    }

    @Test("las recetas existentes no Cookidoo tienen los campos a nil")
    func defaultsAreNil() throws {
        let container = try makeContainer()
        let writing = ModelContext(container)
        writing.insert(Recipe(name: "Tortilla", source: "ia"))
        try writing.save()

        let reading = ModelContext(container)
        let restored = try #require(try reading.fetch(FetchDescriptor<Recipe>()).first)
        #expect(restored.cookidooId == nil)
        #expect(restored.imageURL == nil)
    }
}
```

- [ ] **Step 2: Ejecutar y verlo fallar**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/RecipeCookidooTests`
Expected: FAIL de compilación (`cookidooId` no es miembro de `Recipe`).

- [ ] **Step 3: Implementar los campos**

En `MyFit/Models/Recipe.swift`, añadir las propiedades junto a las demás:

```swift
    /// ID de la receta en Cookidoo (p.ej. "r90756"); nil si no viene de Cookidoo.
    var cookidooId: String?
    /// URL de la foto de la receta (Cookidoo); nil si no tiene.
    var imageURL: String?
```

y los parámetros al final del `init` (con default, no rompe llamadas existentes):

```swift
         cookidooId: String? = nil,
         imageURL: String? = nil,
         createdAt: Date = Date()) {
```
```swift
        self.cookidooId = cookidooId
        self.imageURL = imageURL
```

- [ ] **Step 4: Ejecutar y verlo pasar**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/RecipeCookidooTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MyFit/Models/Recipe.swift MyFitTests/RecipeCookidooTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: campos cookidooId e imageURL en Recipe"
```

### Task 5: `CookidooService` (cliente HTTP + DTOs)

**Files:**
- Create: `MyFit/Services/CookidooService.swift`
- Test: `MyFitTests/CookidooServiceTests.swift`

**Interfaces:**
- Consumes: `BackendService.urlDefaultsKey`, `BackendService.apiKeyAccount`, `BackendError`, `KeychainHelper` (del plan de Speediance); `RecipeSection` (`MyFit/Models/Recipe.swift`).
- Produces (lo usan Tasks 6, 7, 8 y 9):
  - `struct CookidooRecipeSummary: Decodable, Sendable, Identifiable, Hashable { let id: String; let title: String; let imageURL: URL?; let url: URL? }`
  - `struct CookidooSearchResponse: Decodable, Sendable { let recipes: [CookidooRecipeSummary]; let total: Int }`
  - `struct CookidooNutrition: Decodable, Sendable { let calories: Int; let proteinGrams: Double; let carbsGrams: Double; let fatGrams: Double }`
  - `struct CookidooRecipeDetail: Decodable, Sendable { let id: String; let title: String; let imageURL: URL?; let url: URL?; let totalMinutes: Int?; let difficulty: String?; let servings: Int?; let ingredientSections: [RecipeSection]; let stepSections: [RecipeSection]; let nutrition: CookidooNutrition? }`
  - `struct CookidooPlannerDay: Decodable, Sendable { let date: String; let recipes: [CookidooPlannerRecipe] }` y `struct CookidooPlannerRecipe: Decodable, Sendable { let id: String; let title: String; let totalMinutes: Int }`
  - `protocol CookidooServing: Sendable` con `searchRecipes(query:page:)`, `recipeDetail(id:)`, `plannerWeek(containing:)`, `addToPlanner(recipeId:date:)`, `addToShoppingList(recipeId:)`, `cookidooStatus()`.
  - `struct CookidooService: CookidooServing` con `init(baseURL: URL, apiKey: String)` y `static func fromStoredConfiguration() -> CookidooService?`.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/CookidooServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("CookidooService · parsing del JSON del backend")
struct CookidooServiceTests {

    @Test("decodifica una búsqueda con resultados")
    func decodesSearch() throws {
        let json = """
        {"recipes": [{"id": "r90756", "title": "Salmón al vapor",
                      "imageURL": "https://img/r90756.jpg",
                      "url": "https://cookidoo.es/recipes/recipe/es-ES/r90756"}],
         "total": 128}
        """
        let response = try JSONDecoder().decode(CookidooSearchResponse.self, from: Data(json.utf8))
        #expect(response.total == 128)
        #expect(response.recipes.count == 1)
        #expect(response.recipes[0].id == "r90756")
        #expect(response.recipes[0].title == "Salmón al vapor")
        #expect(response.recipes[0].imageURL?.absoluteString == "https://img/r90756.jpg")
    }

    @Test("decodifica una búsqueda vacía")
    func decodesEmptySearch() throws {
        let json = #"{"recipes": [], "total": 0}"#
        let response = try JSONDecoder().decode(CookidooSearchResponse.self, from: Data(json.utf8))
        #expect(response.recipes.isEmpty)
        #expect(response.total == 0)
    }

    @Test("decodifica detalle con nutrición")
    func decodesDetailWithNutrition() throws {
        let json = """
        {"id": "r90756", "title": "Salmón", "imageURL": null, "url": "u",
         "totalMinutes": 35, "difficulty": "fácil", "servings": 4,
         "ingredientSections": [{"title": null, "items": ["800 g de agua"]}],
         "stepSections": [{"title": null, "items": ["Ponga el agua en el vaso."]}],
         "nutrition": {"calories": 320, "proteinGrams": 28.0, "carbsGrams": 6.0, "fatGrams": 18.0}}
        """
        let detail = try JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
        #expect(detail.totalMinutes == 35)
        #expect(detail.servings == 4)
        #expect(detail.ingredientSections[0].items == ["800 g de agua"])
        #expect(detail.nutrition?.calories == 320)
        #expect(detail.nutrition?.proteinGrams == 28.0)
    }

    @Test("decodifica detalle sin nutrición (nutrition null)")
    func decodesDetailWithoutNutrition() throws {
        let json = """
        {"id": "r1", "title": "X", "imageURL": null, "url": "u",
         "totalMinutes": null, "difficulty": null, "servings": null,
         "ingredientSections": [], "stepSections": [], "nutrition": null}
        """
        let detail = try JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
        #expect(detail.nutrition == nil)
        #expect(detail.totalMinutes == nil)
    }

    @Test("decodifica la semana del planificador")
    func decodesPlannerWeek() throws {
        let json = """
        {"days": [{"date": "2026-09-22",
                   "recipes": [{"id": "r90756", "title": "Salmón", "totalMinutes": 35}]}]}
        """
        let week = try JSONDecoder().decode(CookidooPlannerWeekResponse.self, from: Data(json.utf8))
        #expect(week.days.count == 1)
        #expect(week.days[0].recipes[0].id == "r90756")
    }
}
```

- [ ] **Step 2: Ejecutar y verlo fallar**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooServiceTests`
Expected: FAIL de compilación (tipos no existen).

- [ ] **Step 3: Implementar `MyFit/Services/CookidooService.swift`**

```swift
import Foundation

struct CookidooRecipeSummary: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let imageURL: URL?
    let url: URL?
}

struct CookidooSearchResponse: Decodable, Sendable {
    let recipes: [CookidooRecipeSummary]
    let total: Int
}

struct CookidooNutrition: Decodable, Sendable {
    let calories: Int
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
}

struct CookidooRecipeDetail: Decodable, Sendable {
    let id: String
    let title: String
    let imageURL: URL?
    let url: URL?
    let totalMinutes: Int?
    let difficulty: String?
    let servings: Int?
    let ingredientSections: [RecipeSection]
    let stepSections: [RecipeSection]
    /// nil cuando Cookidoo no expone macros: la app los estima por IA.
    let nutrition: CookidooNutrition?
}

struct CookidooPlannerRecipe: Decodable, Sendable {
    let id: String
    let title: String
    let totalMinutes: Int
}

struct CookidooPlannerDay: Decodable, Sendable {
    let date: String
    let recipes: [CookidooPlannerRecipe]
}

struct CookidooPlannerWeekResponse: Decodable, Sendable {
    let days: [CookidooPlannerDay]
}

private struct CookidooShoppingResponse: Decodable {
    let ok: Bool
    let ingredientsAdded: Int
}

private struct CookidooPlannerAddResponse: Decodable {
    let ok: Bool
}

/// Estado de Cookidoo dentro de GET /health del backend.
private struct CookidooHealthResponse: Decodable {
    let cookidoo: String?
}

protocol CookidooServing: Sendable {
    func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse
    func recipeDetail(id: String) async throws -> CookidooRecipeDetail
    func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay]
    func addToPlanner(recipeId: String, date: Date) async throws
    /// Devuelve cuántos ingredientes se añadieron a la lista de la compra.
    func addToShoppingList(recipeId: String) async throws -> Int
    /// "connected" | "error" | "reauth_required" | "not_configured" según /health.
    func cookidooStatus() async throws -> String
}

/// Cliente del router /cookidoo del backend propio. Misma config que BackendService
/// (URL en UserDefaults, API key en Keychain): la app nunca habla con Cookidoo directo.
struct CookidooService: CookidooServing {
    let baseURL: URL
    let apiKey: String

    static func fromStoredConfiguration() -> CookidooService? {
        guard let raw = UserDefaults.standard.string(forKey: BackendService.urlDefaultsKey),
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = KeychainHelper.read(account: BackendService.apiKeyAccount)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
        else { return nil }
        return CookidooService(baseURL: url, apiKey: key)
    }

    func searchRecipes(query: String, page: Int = 0) async throws -> CookidooSearchResponse {
        var components = URLComponents(url: baseURL.appending(path: "cookidoo/recipes/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query),
                                 URLQueryItem(name: "page", value: String(page))]
        return try await get(components.url!, as: CookidooSearchResponse.self)
    }

    func recipeDetail(id: String) async throws -> CookidooRecipeDetail {
        try await get(baseURL.appending(path: "cookidoo/recipes/\(id)"), as: CookidooRecipeDetail.self)
    }

    func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] {
        var components = URLComponents(url: baseURL.appending(path: "cookidoo/planner/week"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "date", value: Self.dayFormatter.string(from: date))]
        let response = try await get(components.url!, as: CookidooPlannerWeekResponse.self)
        return response.days
    }

    func addToPlanner(recipeId: String, date: Date) async throws {
        let body: [String: String] = ["recipeId": recipeId, "date": Self.dayFormatter.string(from: date)]
        _ = try await post(baseURL.appending(path: "cookidoo/planner/add"),
                           body: body, as: CookidooPlannerAddResponse.self)
    }

    func addToShoppingList(recipeId: String) async throws -> Int {
        let response = try await post(baseURL.appending(path: "cookidoo/shopping-list/add-recipe"),
                                      body: ["recipeId": recipeId], as: CookidooShoppingResponse.self)
        return response.ingredientsAdded
    }

    func cookidooStatus() async throws -> String {
        let response = try await get(baseURL.appending(path: "health"), as: CookidooHealthResponse.self)
        return response.cookidoo ?? "desconocido"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 30
        return try await send(request, as: type)
    }

    private func post<T: Decodable>(_ url: URL, body: [String: String], as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return try await send(request, as: type)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        if http.statusCode == 401,
           let body = try? JSONDecoder().decode([String: String].self, from: data),
           body["error"] == "reauth_required" {
            throw BackendError.httpError(status: 401,
                body: "Las credenciales de Cookidoo del backend han caducado. Actualiza el .env del backend.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BackendError.httpError(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.invalidResponse
        }
    }
}
```

- [ ] **Step 4: Ejecutar y verlo pasar**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/CookidooService.swift MyFitTests/CookidooServiceTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: CookidooService con DTOs del backend /cookidoo"
```

### Task 6: `CookidooImporter` (mapeo a `Recipe` + dedup)

**Files:**
- Create: `MyFit/Services/CookidooImporter.swift`
- Test: `MyFitTests/CookidooImporterTests.swift`

**Interfaces:**
- Consumes: `CookidooRecipeDetail` (Task 5), `Recipe`, `RecipeSection`, `RecipeMacros` (`MyFit/Services/RecipeGeneratorService.swift`).
- Produces (lo usan Tasks 7 y 8):
  - `enum CookidooImporter` con `static func existingRecipe(cookidooId: String, in context: ModelContext) -> Recipe?` y `static func makeRecipe(from detail: CookidooRecipeDetail, estimatedMacros: RecipeMacros?) -> Recipe`.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/CookidooImporterTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("CookidooImporter · de detalle Cookidoo a Recipe")
struct CookidooImporterTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private var detail: CookidooRecipeDetail {
        let json = """
        {"id": "r90756", "title": "Salmón al vapor", "imageURL": "https://img/r.jpg", "url": "u",
         "totalMinutes": 35, "difficulty": "fácil", "servings": 4,
         "ingredientSections": [{"title": null, "items": ["800 g de agua", "4 lomos de salmón"]}],
         "stepSections": [{"title": null, "items": ["Ponga el agua en el vaso."]}],
         "nutrition": {"calories": 320, "proteinGrams": 28.0, "carbsGrams": 6.0, "fatGrams": 18.0}}
        """
        return try! JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
    }

    @Test("mapea todos los campos con nutrición real de Cookidoo")
    func mapsDetailWithNutrition() {
        let recipe = CookidooImporter.makeRecipe(from: detail, estimatedMacros: nil)
        #expect(recipe.name == "Salmón al vapor")
        #expect(recipe.source == "cookidoo")
        #expect(recipe.cookidooId == "r90756")
        #expect(recipe.imageURL == "https://img/r.jpg")
        #expect(recipe.ingredientSections[0].items.count == 2)
        #expect(recipe.stepSections[0].items == ["Ponga el agua en el vaso."])
        #expect(recipe.calories == 320)
        #expect(recipe.proteinGrams == 28.0)
    }

    @Test("sin nutrición de Cookidoo usa los macros estimados por IA")
    func fallsBackToEstimatedMacros() throws {
        let json = """
        {"id": "r1", "title": "X", "imageURL": null, "url": "u",
         "totalMinutes": null, "difficulty": null, "servings": null,
         "ingredientSections": [], "stepSections": [], "nutrition": null}
        """
        let noNutrition = try JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
        let estimated = RecipeMacros(calories: 500, proteinGrams: 40, carbsGrams: 30, fatGrams: 20)
        let recipe = CookidooImporter.makeRecipe(from: noNutrition, estimatedMacros: estimated)
        #expect(recipe.calories == 500)
        #expect(recipe.proteinGrams == 40)
    }

    @Test("existingRecipe encuentra duplicados por cookidooId")
    func dedupByCookidooId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Recipe(name: "Salmón", source: "cookidoo", cookidooId: "r90756"))
        try context.save()

        #expect(CookidooImporter.existingRecipe(cookidooId: "r90756", in: context)?.name == "Salmón")
        #expect(CookidooImporter.existingRecipe(cookidooId: "r99999", in: context) == nil)
    }
}
```

- [ ] **Step 2: Ejecutar y verlo fallar**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooImporterTests`
Expected: FAIL de compilación.

- [ ] **Step 3: Implementar `MyFit/Services/CookidooImporter.swift`**

```swift
import Foundation
import SwiftData

/// Convierte un detalle de Cookidoo en una Recipe de MyFit y deduplica por cookidooId.
enum CookidooImporter {
    /// La receta ya importada con ese id de Cookidoo, si existe.
    static func existingRecipe(cookidooId: String, in context: ModelContext) -> Recipe? {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.cookidooId == cookidooId }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Crea la Recipe (sin insertarla). Los macros vienen de Cookidoo si los hay;
    /// si no, de la estimación por IA que pase el llamador (pueden ser nil ambos).
    static func makeRecipe(from detail: CookidooRecipeDetail,
                           estimatedMacros: RecipeMacros?) -> Recipe {
        Recipe(name: detail.title,
               ingredientSections: detail.ingredientSections,
               stepSections: detail.stepSections,
               source: "cookidoo",
               calories: detail.nutrition?.calories ?? estimatedMacros?.calories,
               proteinGrams: detail.nutrition?.proteinGrams ?? estimatedMacros?.proteinGrams,
               carbsGrams: detail.nutrition?.carbsGrams ?? estimatedMacros?.carbsGrams,
               fatGrams: detail.nutrition?.fatGrams ?? estimatedMacros?.fatGrams,
               cookidooId: detail.id,
               imageURL: detail.imageURL?.absoluteString)
    }
}
```

- [ ] **Step 4: Ejecutar y verlo pasar**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooImporterTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/CookidooImporter.swift MyFitTests/CookidooImporterTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: CookidooImporter con dedup por cookidooId"
```

### Task 7: Acciones compartidas + tarjetas de receta en el chat

**Files:**
- Create: `MyFit/Services/CookidooActions.swift`
- Create: `MyFit/Services/CookidooActionResolver.swift`
- Create: `MyFit/Views/Recipes/CookidooRecipeCard.swift`
- Modify: `MyFit/Services/NutritionChatService.swift` (`ChatMessage`, `send`, system prompt)
- Modify: `MyFit/Views/Assistant/NutritionChatView.swift` (tarjetas bajo la burbuja)
- Test: `MyFitTests/CookidooChatActionTests.swift`

**Interfaces:**
- Consumes: `CookidooServing` (Task 5), `CookidooImporter` (Task 6), `RecipeGeneratorService.estimateMacros`, `AIServicePrompt.extractJSON`.
- Produces:
  - `@MainActor final class CookidooActions: ObservableObject` con `init(cookidoo: any CookidooServing, generator: RecipeGeneratorService)`, `@Published var notice: String?`, y `func importRecipe(id:into:) async -> Recipe?`, `func plan(recipeId:date:) async -> Bool`, `func addToShoppingList(recipeId:) async -> Bool`. Lo usan chat (Task 7) y vista dedicada (Task 8).
  - `struct CookidooActionResolver: Sendable` con `init(cookidoo: any CookidooServing)` y `func resolve(reply: String) async throws -> (followUp: String, recipes: [CookidooRecipeSummary])?`.
  - `NutritionChatService.parseCookidooAction(_ text: String) -> CookidooChatAction?` (static, pura).
  - `ChatMessage.cookidooRecipes: [CookidooRecipeSummary]?` (default nil; no se persiste).
  - `CookidooRecipeCard` (vista) con `init(summary: CookidooRecipeSummary, actions: CookidooActions, modelContext: ModelContext)` — botones Importar / Planificar / A la compra.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/CookidooChatActionTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("Chat · acción Cookidoo")
struct CookidooChatActionTests {

    @Test("extrae la acción de búsqueda de un reply JSON")
    func parsesSearchAction() {
        let reply = #"{"action": "search_cookidoo", "query": "cena alta en proteína"}"#
        let action = NutritionChatService.parseCookidooAction(reply)
        #expect(action?.action == "search_cookidoo")
        #expect(action?.query == "cena alta en proteína")
    }

    @Test("tolera texto alrededor del JSON")
    func parsesActionWithSurroundingText() {
        let reply = "Claro, busco en Cookidoo:\n{\"action\": \"search_cookidoo\", \"query\": \"salmón\"}"
        #expect(NutritionChatService.parseCookidooAction(reply)?.query == "salmón")
    }

    @Test("un reply normal no es acción")
    func plainReplyIsNotAction() {
        #expect(NutritionChatService.parseCookidooAction("Te recomiendo lentejas.") == nil)
    }

    @Test("un JSON que no es acción cookidoo se ignora")
    func unrelatedJSONIgnored() {
        #expect(NutritionChatService.parseCookidooAction(#"{"foo": 1}"#) == nil)
    }

    @Test("el resolver ejecuta la búsqueda y devuelve followUp con títulos y macros")
    func resolverSearches() async throws {
        struct Stub: CookidooServing {
            func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse {
                CookidooSearchResponse(recipes: [
                    CookidooRecipeSummary(id: "r1", title: "Salmón al vapor", imageURL: nil, url: nil),
                    CookidooRecipeSummary(id: "r2", title: "Pollo al limón", imageURL: nil, url: nil),
                ], total: 2)
            }
            func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
            func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
            func addToPlanner(recipeId: String, date: Date) async throws {}
            func addToShoppingList(recipeId: String) async throws -> Int { 0 }
            func cookidooStatus() async throws -> String { "connected" }
        }
        let resolver = CookidooActionResolver(cookidoo: Stub())
        let result = try await resolver.resolve(
            reply: #"{"action": "search_cookidoo", "query": "salmón"}"#,
            remainingMacros: "Restante hoy: 800 kcal · P60/C40/G20 g.")
        #expect(result?.recipes.map(\.id) == ["r1", "r2"])
        #expect(result?.followUp.contains("Salmón al vapor") == true)
        #expect(result?.followUp.contains("800 kcal") == true)
    }

    @Test("el resolver devuelve nil si el reply no es acción")
    func resolverIgnoresPlainReply() async throws {
        struct Stub: CookidooServing {
            func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse {
                Issue.record("no debería buscar"); throw BackendError.invalidResponse
            }
            func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
            func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
            func addToPlanner(recipeId: String, date: Date) async throws {}
            func addToShoppingList(recipeId: String) async throws -> Int { 0 }
            func cookidooStatus() async throws -> String { "connected" }
        }
        let resolver = CookidooActionResolver(cookidoo: Stub())
        #expect(try await resolver.resolve(reply: "Hola", remainingMacros: "") == nil)
    }
}
```

- [ ] **Step 2: Ejecutar y verlo fallar**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooChatActionTests`
Expected: FAIL de compilación.

- [ ] **Step 3: Implementar `CookidooActionResolver.swift`**

```swift
import Foundation

/// Acción estructurada que el asistente emite cuando quiere buscar en Cookidoo.
struct CookidooChatAction: Codable {
    var action: String
    var query: String?
}

/// Resuelve la acción search_cookidoo de un reply del asistente:
/// ejecuta la búsqueda contra el backend y prepara el prompt de seguimiento
/// para que el LLM elija y explique 2-3 recetas con los macros restantes.
struct CookidooActionResolver: Sendable {
    let cookidoo: any CookidooServing

    /// Devuelve nil si el reply no es una acción Cookidoo.
    func resolve(reply: String, remainingMacros: String) async throws -> (followUp: String, recipes: [CookidooRecipeSummary])? {
        guard let action = NutritionChatService.parseCookidooAction(reply),
              action.action == "search_cookidoo",
              let query = action.query, !query.isEmpty else { return nil }

        let response = try await cookidoo.searchRecipes(query: query, page: 0)
        let recipes = Array(response.recipes.prefix(5))
        let list = recipes.map { "- \($0.title) [id: \($0.id)]" }.joined(separator: "\n")
        let followUp = """
        Resultados de Cookidoo para "\(query)" (\(response.total) en total):
        \(list.isEmpty ? "(sin resultados)" : list)

        \(remainingMacros)

        Elige las 2-3 que mejor encajen con lo que le queda hoy al usuario y \
        explica brevemente por qué. Menciona solo recetas de la lista, por su nombre exacto. \
        Si no hay resultados, dilo y ofrece generar una receta propia.
        """
        return (followUp, Array(recipes.prefix(3)))
    }
}
```

- [ ] **Step 4: Implementar `CookidooActions.swift`**

```swift
import Foundation
import SwiftData

/// Acciones sobre una receta de Cookidoo, compartidas por el chat y la vista dedicada.
@MainActor
final class CookidooActions: ObservableObject {
    @Published var notice: String?
    @Published var isWorking = false

    private let cookidoo: any CookidooServing
    private let generator: RecipeGeneratorService

    init(cookidoo: any CookidooServing, generator: RecipeGeneratorService = RecipeGeneratorService()) {
        self.cookidoo = cookidoo
        self.generator = generator
    }

    /// Importa la receta a MyFit. Si ya existe (mismo cookidooId) devuelve la existente.
    /// Si Cookidoo no da macros, los estima por IA.
    func importRecipe(id: String, into context: ModelContext) async -> Recipe? {
        if let existing = CookidooImporter.existingRecipe(cookidooId: id, in: context) {
            notice = "Ya tenías \"\(existing.name)\" importada."
            return existing
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let detail = try await cookidoo.recipeDetail(id: id)
            var estimated: RecipeMacros?
            if detail.nutrition == nil {
                let ingredients = detail.ingredientSections.flatMap(\.items)
                estimated = try? await generator.estimateMacros(recipeName: detail.title,
                                                                ingredients: ingredients)
            }
            let recipe = CookidooImporter.makeRecipe(from: detail, estimatedMacros: estimated)
            context.insert(recipe)
            try? context.save()
            notice = detail.nutrition == nil
                ? "\"\(recipe.name)\" importada (macros estimados por IA)."
                : "\"\(recipe.name)\" importada."
            return recipe
        } catch {
            notice = "No se pudo importar: \(error.localizedDescription)"
            return nil
        }
    }

    /// Añade la receta al planificador de Cookidoo (aparece en la TM6).
    func plan(recipeId: String, date: Date) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            try await cookidoo.addToPlanner(recipeId: recipeId, date: date)
            notice = "Planificada. La verás en tu Thermomix ese día."
            return true
        } catch {
            notice = "No se pudo planificar: \(error.localizedDescription)"
            return false
        }
    }

    /// Añade los ingredientes a la lista de la compra de Cookidoo.
    func addToShoppingList(recipeId: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        do {
            let n = try await cookidoo.addToShoppingList(recipeId: recipeId)
            notice = "\(n) ingredientes añadidos a la lista de la compra de Cookidoo."
            return true
        } catch {
            notice = "No se pudo añadir a la compra: \(error.localizedDescription)"
            return false
        }
    }
}
```

- [ ] **Step 5: Implementar `CookidooRecipeCard.swift`**

```swift
import SwiftUI
import SwiftData

/// Tarjeta de receta de Cookidoo con las acciones Importar / Planificar / A la compra.
/// Se usa en el chat (bajo la burbuja del asistente) y en los resultados de búsqueda.
struct CookidooRecipeCard: View {
    let summary: CookidooRecipeSummary
    @ObservedObject var actions: CookidooActions
    @Environment(\.modelContext) private var modelContext
    @State private var showPlanPicker = false
    @State private var planDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AsyncImage(url: summary.imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(summary.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Importar") {
                    Task { _ = await actions.importRecipe(id: summary.id, into: modelContext) }
                }
                Button("Planificar") { showPlanPicker = true }
                Button("A la compra") {
                    Task { _ = await actions.addToShoppingList(recipeId: summary.id) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(actions.isWorking)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showPlanPicker) {
            NavigationStack {
                DatePicker("Día", selection: $planDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Planificar en Thermomix")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Planificar") {
                                showPlanPicker = false
                                Task { _ = await actions.plan(recipeId: summary.id, date: planDate) }
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { showPlanPicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}
```

- [ ] **Step 6: Integrar en `NutritionChatService`**

En `ChatMessage` (mismo fichero), añadir la propiedad opcional (no se persiste en `ChatMessageRecord`):

```swift
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    /// Tarjetas de recetas de Cookidoo adjuntas a este mensaje (solo en sesión).
    var cookidooRecipes: [CookidooRecipeSummary]? = nil

    enum Role { case user, assistant }
}
```

Añadir a `NutritionChatService`:

```swift
    /// Parsea una posible acción Cookidoo (JSON) en un reply del asistente.
    static func parseCookidooAction(_ text: String) -> CookidooChatAction? {
        guard let data = try? AIServicePrompt.extractJSON(from: text),
              let action = try? JSONDecoder().decode(CookidooChatAction.self, from: data),
              action.action == "search_cookidoo" else { return nil }
        return action
    }
```

En el system prompt (tras las "Normas:"), añadir:

```swift
        prompt += "\n\n" + """
        Búsqueda en Cookidoo (Thermomix):
        - Cuando el usuario pida ideas de recetas para cocinar con la Thermomix o mencione Cookidoo, \
        NO respondas con texto: responde SOLO con un JSON así: \
        {"action": "search_cookidoo", "query": "<búsqueda en español, con los criterios del usuario>"}
        - Tras la búsqueda recibirás los resultados reales: elige 2-3 y explícalos. \
        Nunca inventes recetas de Cookidoo ni des por hecho que existen.
        """
```

En `send(_:)`, tras obtener `reply`, resolver la posible acción antes de pintar el mensaje:

```swift
        chatTask = Task {
            do {
                var reply = try await callChat(userText: text)
                var cards: [CookidooRecipeSummary]?
                if let cookidoo = CookidooService.fromStoredConfiguration(),
                   let resolution = try? await CookidooActionResolver(cookidoo: cookidoo)
                        .resolve(reply: reply, remainingMacros: remainingMacrosSummary()) {
                    reply = try await callChat(userText: resolution.followUp)
                    cards = resolution.recipes
                } else if Self.parseCookidooAction(reply) != nil {
                    // Backend no configurado o búsqueda fallida: respuesta sin Cookidoo.
                    reply = "Ahora mismo no puedo consultar Cookidoo (backend no configurado o no accesible). ¿Quieres que te genere una receta mía mientras tanto?"
                }
                if !Task.isCancelled {
                    messages.append(ChatMessage(role: .assistant, content: reply, cookidooRecipes: cards))
                    persistMessage(role: .assistant, content: reply)
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            isThinking = false
        }
```

Y el resumen de macros restantes (extraído de lo que ya calcula `buildUserDataSection`):

```swift
    /// "Restante hoy: 800 kcal · P60/C40/G20 g." o "" si no hay objetivos configurados.
    private func remainingMacrosSummary() -> String {
        let kcalGoal = UserDefaults.standard.integer(forKey: SyncService.calorieGoalKey)
        guard kcalGoal > 0, let context = modelContext else { return "" }
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Meal>(predicate: #Predicate { $0.date >= today })
        guard let meals = try? context.fetch(descriptor) else { return "" }
        let kcal = meals.reduce(0) { $0 + $1.calories }
        let protein = Int(meals.reduce(0.0) { $0 + $1.proteinGrams })
        let carbs = Int(meals.reduce(0.0) { $0 + $1.carbsGrams })
        let fat = Int(meals.reduce(0.0) { $0 + $1.fatGrams })
        return "Restante hoy: \(kcalGoal - kcal) kcal · P\(UserDefaults.standard.integer(forKey: "dailyProteinGoal") - protein)/C\(UserDefaults.standard.integer(forKey: "dailyCarbsGoal") - carbs)/G\(UserDefaults.standard.integer(forKey: "dailyFatGoal") - fat) g."
    }
```

En `NutritionChatView.swift`:

1. Añadir un `@StateObject` de acciones junto al service:

```swift
    @StateObject private var cookidooActions = CookidooActions(
        cookidoo: CookidooService.fromStoredConfiguration() ?? UnconfiguredCookidooService()
    )
```

y el stub para cuando el backend no está configurado (en `CookidooService.swift`):

```swift
/// Placeholder cuando el backend no está configurado: toda acción informa del problema.
struct UnconfiguredCookidooService: CookidooServing {
    private func fail() -> BackendError { .notConfigured }
    func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse { throw fail() }
    func recipeDetail(id: String) async throws -> CookidooRecipeDetail { throw fail() }
    func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { throw fail() }
    func addToPlanner(recipeId: String, date: Date) async throws { throw fail() }
    func addToShoppingList(recipeId: String) async throws -> Int { throw fail() }
    func cookidooStatus() async throws -> String { "not_configured" }
}
```

2. En `MessageBubble`, bajo el `Text(message.content)`, mostrar las tarjetas cuando las haya. Como `MessageBubble` es privada de la vista, pasarle las acciones:

```swift
    let message: ChatMessage
    var cookidooActions: CookidooActions?
```
```swift
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    // ... mantener aquí los modificadores existentes del Text
                    // (font, padding, background, foregroundStyle) tal cual están
                if let recipes = message.cookidooRecipes, let actions = cookidooActions {
                    ForEach(recipes) { summary in
                        CookidooRecipeCard(summary: summary, actions: actions)
                    }
                }
            }
```

y en el `ForEach` de la lista: `MessageBubble(message: msg, cookidooActions: cookidooActions)`.

3. Aviso de acciones: tras el `Divider()`, si `cookidooActions.notice != nil`, mostrarlo como `Text(...).font(.caption)` con un botón de cerrar que ponga `notice = nil` (o un `.alert` simple ligado al notice).

- [ ] **Step 7: Ejecutar los tests**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooChatActionTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add MyFit/Services/CookidooActions.swift MyFit/Services/CookidooActionResolver.swift MyFit/Views/Recipes/CookidooRecipeCard.swift MyFit/Services/NutritionChatService.swift MyFit/Views/Assistant/NutritionChatView.swift MyFit/Services/CookidooService.swift MyFitTests/CookidooChatActionTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: búsqueda Cookidoo desde el chat con tarjetas de receta"
```

### Task 8: Vista dedicada `CookidooSearchView`

**Files:**
- Create: `MyFit/Views/Recipes/CookidooSearchView.swift`
- Modify: `MyFit/Views/Recipes/RecipeListView.swift` (entrada en toolbar)
- Test: `MyFitTests/CookidooSearchViewModelTests.swift`

**Interfaces:**
- Consumes: `CookidooServing` (Task 5), `CookidooActions` y `CookidooRecipeCard` (Task 7), `UnconfiguredCookidooService` (Task 7).
- Produces: `@MainActor final class CookidooSearchViewModel: ObservableObject` con `init(cookidoo: any CookidooServing)`, `@Published var query = ""`, `@Published var results: [CookidooRecipeSummary] = []`, `@Published var total = 0`, `@Published var isLoading = false`, `@Published var errorMessage: String?`, `@Published var hasSearched = false`, `func search() async`.

- [ ] **Step 1: Escribir los tests que fallan**

`MyFitTests/CookidooSearchViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("CookidooSearchViewModel")
struct CookidooSearchViewModelTests {

    private struct Stub: CookidooServing {
        var response: CookidooSearchResponse
        func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse { response }
        func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
        func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
        func addToPlanner(recipeId: String, date: Date) async throws {}
        func addToShoppingList(recipeId: String) async throws -> Int { 0 }
        func cookidooStatus() async throws -> String { "connected" }
    }

    private struct FailingStub: CookidooServing {
        func searchRecipes(query: String, page: Int) async throws -> CookidooSearchResponse {
            throw BackendError.httpError(status: 502, body: "down")
        }
        func recipeDetail(id: String) async throws -> CookidooRecipeDetail { fatalError() }
        func plannerWeek(containing date: Date) async throws -> [CookidooPlannerDay] { [] }
        func addToPlanner(recipeId: String, date: Date) async throws {}
        func addToShoppingList(recipeId: String) async throws -> Int { 0 }
        func cookidooStatus() async throws -> String { "error" }
    }

    @Test("search rellena resultados y total")
    @MainActor
    func searchFillsResults() async {
        let vm = CookidooSearchViewModel(cookidoo: Stub(response: CookidooSearchResponse(recipes: [
            CookidooRecipeSummary(id: "r1", title: "Salmón", imageURL: nil, url: nil),
        ], total: 42)))
        vm.query = "salmón"
        await vm.search()
        #expect(vm.results.map(\.id) == ["r1"])
        #expect(vm.total == 42)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasSearched)
    }

    @Test("búsqueda sin resultados deja la lista vacía sin error")
    @MainActor
    func emptySearchIsNotAnError() async {
        let vm = CookidooSearchViewModel(cookidoo: Stub(response: CookidooSearchResponse(recipes: [], total: 0)))
        vm.query = "xyz"
        await vm.search()
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasSearched)
    }

    @Test("error del backend se muestra como mensaje")
    @MainActor
    func backendErrorShowsMessage() async {
        let vm = CookidooSearchViewModel(cookidoo: FailingStub())
        vm.query = "salmón"
        await vm.search()
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}
```

- [ ] **Step 2: Ejecutar y verlo fallar**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooSearchViewModelTests`
Expected: FAIL de compilación.

- [ ] **Step 3: Implementar `CookidooSearchView.swift`**

```swift
import SwiftUI
import SwiftData

@MainActor
final class CookidooSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [CookidooRecipeSummary] = []
    @Published var total = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private let cookidoo: any CookidooServing

    init(cookidoo: any CookidooServing) {
        self.cookidoo = cookidoo
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await cookidoo.searchRecipes(query: q, page: 0)
            results = response.recipes
            total = response.total
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
        hasSearched = true
    }
}

/// Buscador de recetas de Cookidoo con las mismas acciones que las tarjetas del chat.
struct CookidooSearchView: View {
    @StateObject private var viewModel: CookidooSearchViewModel
    @StateObject private var actions: CookidooActions
    @Environment(\.dismiss) private var dismiss

    init() {
        let service: any CookidooServing = CookidooService.fromStoredConfiguration()
            ?? UnconfiguredCookidooService()
        _viewModel = StateObject(wrappedValue: CookidooSearchViewModel(cookidoo: service))
        _actions = StateObject(wrappedValue: CookidooActions(cookidoo: service))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Buscando en Cookidoo…")
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("No se pudo buscar", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if viewModel.hasSearched && viewModel.results.isEmpty {
                    ContentUnavailableView {
                        Label("Sin resultados", systemImage: "magnifyingglass")
                    } description: {
                        Text("Prueba con otros términos.")
                    }
                } else {
                    List(viewModel.results) { summary in
                        CookidooRecipeCard(summary: summary, actions: actions)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Buscar en Cookidoo")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.query, prompt: "Receta, ingrediente…")
            .onSubmit(of: .search) { Task { await viewModel.search() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice = actions.notice {
                    Text(notice)
                        .font(.caption)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom)
                        .onTapGesture { actions.notice = nil }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Vista de detalle `CookidooRecipeDetailView`**

El spec pide una vista de detalle con ingredientes, pasos y macros antes de importar. Añadir al final de `CookidooSearchView.swift`:

```swift
/// Detalle de una receta de Cookidoo: carga ingredientes, pasos y macros al aparecer.
struct CookidooRecipeDetailView: View {
    let summary: CookidooRecipeSummary
    let cookidoo: any CookidooServing
    @ObservedObject var actions: CookidooActions
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var detail: CookidooRecipeDetail?
    @State private var loadError: String?
    @State private var showPlanPicker = false
    @State private var planDate = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let detail {
                    detailContent(detail)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("No se pudo cargar", systemImage: "exclamationmark.triangle")
                    } description: { Text(loadError) }
                } else {
                    ProgressView("Cargando receta…")
                }
            }
            .navigationTitle(summary.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .task {
                do {
                    detail = try await cookidoo.recipeDetail(id: summary.id)
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ detail: CookidooRecipeDetail) -> some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AsyncImage(url: detail.imageURL) { $0.resizable().scaledToFill() }
                        placeholder: { Image(systemName: "fork.knife") }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        if let minutes = detail.totalMinutes {
                            Label("\(minutes) min", systemImage: "clock")
                        }
                        if let difficulty = detail.difficulty {
                            Label(difficulty, systemImage: "chart.bar")
                        }
                        if let servings = detail.servings {
                            Label("\(servings) raciones", systemImage: "person.2")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let nutrition = detail.nutrition {
                    Text("\(nutrition.calories) kcal · P \(Int(nutrition.proteinGrams)) g · C \(Int(nutrition.carbsGrams)) g · G \(Int(nutrition.fatGrams)) g (por ración)")
                        .font(.caption)
                } else {
                    Text("Cookidoo no publica macros de esta receta; se estimarán por IA al importarla.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            ForEach(Array(detail.ingredientSections.enumerated()), id: \.offset) { _, section in
                Section(section.title ?? "Ingredientes") {
                    ForEach(section.items, id: \.self) { Text($0) }
                }
            }
            ForEach(Array(detail.stepSections.enumerated()), id: \.offset) { _, section in
                Section(section.title ?? "Preparación") {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }
            Section {
                Button("Importar a MyFit") {
                    Task {
                        if await actions.importRecipe(id: summary.id, into: modelContext) != nil {
                            dismiss()
                        }
                    }
                }
                Button("Planificar en Thermomix") { showPlanPicker = true }
                Button("Añadir a la lista de la compra") {
                    Task { _ = await actions.addToShoppingList(recipeId: summary.id) }
                }
            }
            .disabled(actions.isWorking)
        }
        .sheet(isPresented: $showPlanPicker) {
            NavigationStack {
                DatePicker("Día", selection: $planDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .navigationTitle("Planificar en Thermomix")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Planificar") {
                                showPlanPicker = false
                                Task { _ = await actions.plan(recipeId: summary.id, date: planDate) }
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancelar") { showPlanPicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}
```

Para abrirlo desde los resultados: en `CookidooRecipeCard` añadir la propiedad opcional `var onOpen: (() -> Void)? = nil` y sobre el `HStack` del título `.contentShape(Rectangle()).onTapGesture { onOpen?() }`. En el `List` de `CookidooSearchView`, pasar el closure con un `@State private var openedRecipe: CookidooRecipeSummary?` y un sheet:

```swift
                    List(viewModel.results) { summary in
                        CookidooRecipeCard(summary: summary, actions: actions,
                                           onOpen: { openedRecipe = summary })
                    }
                    .listStyle(.plain)
```
```swift
            .sheet(item: $openedRecipe) { summary in
                CookidooRecipeDetailView(summary: summary,
                                         cookidoo: CookidooService.fromStoredConfiguration()
                                            ?? UnconfiguredCookidooService(),
                                         actions: actions)
            }
```

- [ ] **Step 5: Entrada desde `RecipeListView`**

En `MyFit/Views/Recipes/RecipeListView.swift`, convertir el botón "+" de la toolbar en un menú con las dos opciones:

```swift
    @State private var showGenerator = false
    @State private var showCookidooSearch = false
```
```swift
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Generar con IA", systemImage: "sparkles") { showGenerator = true }
                    Button("Buscar en Cookidoo", systemImage: "magnifyingglass") { showCookidooSearch = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
```
```swift
        .sheet(isPresented: $showCookidooSearch) {
            CookidooSearchView()
        }
```

Y actualizar el texto del estado vacío: `"Genera tu primera receta con IA o búscala en Cookidoo con el botón +."`

- [ ] **Step 6: Ejecutar los tests**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/CookidooSearchViewModelTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add MyFit/Views/Recipes/CookidooSearchView.swift MyFit/Views/Recipes/RecipeListView.swift MyFitTests/CookidooSearchViewModelTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: vista de búsqueda Cookidoo en la sección Recetas"
```

### Task 9: Estado Cookidoo en Ajustes

**Files:**
- Modify: `MyFit/Views/Settings/SettingsView.swift` (sección del backend creada por el plan de Speediance)
- Modify: `MyFit/Services/BackendService.swift` (decodificar el campo `cookidoo` de `/health`)
- Test: `MyFitTests/BackendServiceTests.swift` (extender)

**Interfaces:**
- Consumes: `GET /health` con `cookidoo` (Task 3), la sección de backend en SettingsView (plan de Speediance).
- Produces: `BackendService.checkHealthDetails() async throws -> (speediance: String, cookidoo: String?)` (nuevo; `checkHealth()` se mantiene).

- [ ] **Step 1: Extender el test de BackendService**

Añadir a `MyFitTests/BackendServiceTests.swift`:

```swift
    @Test("decodifica /health con estado de Cookidoo")
    func decodesHealthWithCookidoo() throws {
        let json = #"{"status": "ok", "speediance": "connected", "cookidoo": "reauth_required"}"#
        let health = try JSONDecoder().decode(BackendHealthResponse.self, from: Data(json.utf8))
        #expect(health.speediance == "connected")
        #expect(health.cookidoo == "reauth_required")
    }

    @Test("decodifica /health antiguo sin campo cookidoo")
    func decodesHealthWithoutCookidoo() throws {
        let json = #"{"status": "ok", "speediance": "connected"}"#
        let health = try JSONDecoder().decode(BackendHealthResponse.self, from: Data(json.utf8))
        #expect(health.cookidoo == nil)
    }
```

(`BackendHealthResponse` es `private` en el plan de Speediance: quitarle el `private` para testearlo, y añadir `let cookidoo: String?`.)

- [ ] **Step 2: Ejecutar y verlo fallar**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/BackendServiceTests`
Expected: FAIL de compilación (`cookidoo` no es miembro).

- [ ] **Step 3: Implementar**

En `BackendService.swift`:

```swift
struct BackendHealthResponse: Decodable {
    let status: String
    let speediance: String
    let cookidoo: String?
}
```

y añadir al protocolo y a `BackendService`:

```swift
    /// Estado detallado del backend: Speediance y Cookidoo.
    func checkHealthDetails() async throws -> BackendHealthResponse
```

(reimplementar `checkHealth()` como `try await checkHealthDetails().speediance == "connected"` para no duplicar la llamada).

En `SettingsView.swift`, en la sección del backend, tras el resultado del botón "Probar conexión", añadir una línea con el estado de Cookidoo cuando la prueba es OK:

```swift
    // junto al resultado existente de la prueba de conexión
    if let cookidooStatus {
        Label("Cookidoo: \(cookidooStatus)", systemImage: "fork.knife")
            .font(.caption)
            .foregroundStyle(cookidooStatus == "connected" ? .green : .orange)
    }
```

con `@State private var cookidooStatus: String?` rellenado desde `checkHealthDetails().cookidoo` al pulsar "Probar conexión", y texto traducido: mapear `"connected"` → "conectado", `"not_configured"` → "sin configurar en el backend", `"reauth_required"` → "credenciales caducadas (revisar .env del backend)", resto → "error".

- [ ] **Step 4: Ejecutar y verlo pasar**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet -only-testing:MyFitTests/BackendServiceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/BackendService.swift MyFit/Views/Settings/SettingsView.swift MyFitTests/BackendServiceTests.swift
git commit -m "feat: estado de Cookidoo en la prueba de conexión de Ajustes"
```

### Task 10: Verificación end-to-end manual

Sin tests automáticos — checklist manual con la cuenta real (requiere backend arrancado con credenciales Cookidoo en `.env`):

- [ ] `cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000` arranca sin errores y crea `.cookidoo-token.json` al primer uso.
- [ ] En Ajustes de la app, "Probar conexión" muestra Speediance y Cookidoo en verde.
- [ ] En Recetas → + → "Buscar en Cookidoo": buscar "salmón" devuelve resultados con foto.
- [ ] Importar una receta: aparece en la lista de recetas con badge, ingredientes, pasos legibles (sin HTML) y macros.
- [ ] Importar la misma receta otra vez: avisa de que ya existe, no duplica.
- [ ] Planificar la receta para mañana: en la app oficial de Cookidoo aparece en "Mi semana" ese día, y al encender la TM6 aparece para Cocina Guiada.
- [ ] "A la compra": los ingredientes aparecen en la lista de la compra de la app oficial de Cookidoo.
- [ ] En el chat: "búscame una cena alta en proteína para la Thermomix" → el asistente propone 2-3 recetas reales de Cookidoo con tarjetas y sus botones funcionan.
- [ ] Con el Mac apagado: el chat ofrece generar receta propia en vez de quedarse colgado.
