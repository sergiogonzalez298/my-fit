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


def test_recipe_details_ok(client, monkeypatch):
    async def fake(settings, recipe_id):
        return {
            "id": recipe_id,
            "title": "Salmón",
            "imageURL": None,
            "url": "u",
            "totalMinutes": 30,
            "difficulty": "easy",
            "servings": 2,
            "ingredientSections": [{"title": None, "items": ["200 g salmón"]}],
            "stepSections": [{"title": None, "items": ["Cocinar"]}],
            "nutrition": None,
        }
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "recipe_details", fake)
    r = client.get("/cookidoo/recipes/r1", headers={"X-API-Key": "secret"})
    assert r.status_code == 200
    assert r.json()["id"] == "r1"
    assert r.json()["title"] == "Salmón"


def test_planner_week_ok(client, monkeypatch):
    async def fake(settings, day):
        return {"days": [{"date": day.isoformat(), "recipes": []}]}
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "calendar_week", fake)
    r = client.get("/cookidoo/planner/week?date=2026-09-22",
                   headers={"X-API-Key": "secret"})
    assert r.status_code == 200
    assert r.json() == {"days": [{"date": "2026-09-22", "recipes": []}]}


def test_upstream_error_mapea_a_502(client, monkeypatch):
    async def fake(settings, query, page=0):
        raise RuntimeError("upstream down")
    monkeypatch.setattr(cookidoo_router.cookidoo_client, "search_recipes", fake)
    r = client.get("/cookidoo/recipes/search?q=x", headers={"X-API-Key": "secret"})
    assert r.status_code == 502
    assert r.json() == {"error": "cookidoo_error", "detail": "upstream down"}
