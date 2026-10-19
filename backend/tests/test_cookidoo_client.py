import os
import stat
from datetime import date
from types import SimpleNamespace

import pytest
from cookidoo_api.exceptions import CookidooAuthException

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


@pytest.mark.asyncio
async def test_recipe_details_mapea_a_json_propio(monkeypatch):
    details = SimpleNamespace(
        id="r90756", name="Salmón al vapor",
        ingredients=[SimpleNamespace(id="i1", name="salmón", description="200 g de salmón", preparation=None)],
        thumbnail=None, image="https://img/r90756.jpg",
        url="https://cookidoo.es/recipes/recipe/es-ES/r90756",
        difficulty="easy", notes=[], categories=[], collections=[], utensils=[],
        serving_size=2, active_time=300, total_time=1800, nutrition_groups=[],
        step_groups=[SimpleNamespace(title="Preparación", recipe_steps=[
            SimpleNamespace(title="Paso 1", formatted_text="<p>Cocer &amp; servir.</p>"),
        ])],
    )

    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path): pass
        async def login(self): pass
        async def get_recipe_details(self, recipe_id):
            assert recipe_id == "r90756"
            return details

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    result = await cookidoo_client.recipe_details(TEST_SETTINGS, "r90756")
    assert result == {
        "id": "r90756", "title": "Salmón al vapor",
        "imageURL": "https://img/r90756.jpg",
        "url": "https://cookidoo.es/recipes/recipe/es-ES/r90756",
        "totalMinutes": 30, "difficulty": "easy", "servings": 2,
        "ingredientSections": [{"title": None, "items": ["200 g de salmón"]}],
        "stepSections": [{"title": "Preparación", "items": ["Cocer & servir."]}],
        "nutrition": None,
    }


@pytest.mark.asyncio
async def test_calendar_week_mapea_a_json_propio(monkeypatch):
    day = date(2026, 9, 22)
    calendar_day = SimpleNamespace(
        id="2026-09-22", title="2026-09-22", customer_recipe_ids=[],
        recipes=[SimpleNamespace(
            id="r90756", name="Salmón al vapor", total_time=1500,
            thumbnail=None, image="https://img/r90756.jpg",
            url="https://cookidoo.es/recipes/recipe/es-ES/r90756", is_custom=False,
        )],
    )

    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path): pass
        async def login(self): pass
        async def get_recipes_in_calendar_week(self, requested_day):
            assert requested_day == day
            return [calendar_day]

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    result = await cookidoo_client.calendar_week(TEST_SETTINGS, day)
    assert result == {"days": [{
        "date": "2026-09-22",
        "recipes": [{"id": "r90756", "title": "Salmón al vapor", "totalMinutes": 25}],
    }]}


@pytest.mark.asyncio
async def test_add_recipe_to_calendar(monkeypatch):
    day = date(2026, 9, 22)

    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path): pass
        async def login(self): pass
        async def add_recipes_to_calendar(self, requested_day, recipe_ids):
            assert requested_day == day
            assert recipe_ids == ["r90756"]

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    result = await cookidoo_client.add_recipe_to_calendar(TEST_SETTINGS, "r90756", day)
    assert result is None


@pytest.mark.asyncio
async def test_add_recipe_to_shopping_list_devuelve_numero_ingredientes(monkeypatch):
    items = [
        SimpleNamespace(id="i1", name="salmón", is_owned=False,
                        description="200 g de salmón", preparation=None),
        SimpleNamespace(id="i2", name="agua", is_owned=False,
                        description="100 g de agua", preparation=None),
    ]

    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path): pass
        async def login(self): pass
        async def add_ingredient_items_for_recipes(self, recipe_ids):
            assert recipe_ids == ["r90756"]
            return items

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    result = await cookidoo_client.add_recipe_to_shopping_list(TEST_SETTINGS, "r90756")
    assert result == 2


@pytest.mark.asyncio
async def test_token_se_guarda_con_permisos_600(monkeypatch, tmp_path):
    token_file = tmp_path / "token.json"

    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): raise FileNotFoundError()
        def save_token(self, path):
            with open(path, "w") as f:
                f.write("{}")
        async def login(self):
            self.on_auth_data_update(None)
        async def search_recipes(self, query, page=None, **kw):
            return SimpleNamespace(recipes=[], total=0)

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    monkeypatch.setattr(cookidoo_client, "_TOKEN_PATH", token_file)
    await cookidoo_client.search_recipes(TEST_SETTINGS, "salmón")
    assert stat.S_IMODE(os.stat(token_file).st_mode) == 0o600


@pytest.mark.asyncio
async def test_credenciales_ausentes_lanzan_reauth():
    settings = Settings(email="t@example.com", password="pw", region="EU", api_key="secret")
    with pytest.raises(cookidoo_client.CookidooReauthRequired):
        await cookidoo_client.search_recipes(settings, "salmón")


@pytest.mark.asyncio
async def test_token_rechazado_reloguea_y_reintenta(monkeypatch):
    class FakeCookidoo:
        def __init__(self, *a, **kw):
            self.logged_in = False
        on_auth_data_update = None
        def load_token(self, path): pass
        def save_token(self, path): pass
        async def login(self): self.logged_in = True
        async def search_recipes(self, query, page=None, **kw):
            if not self.logged_in:
                raise CookidooAuthException("refresh failed")
            return SimpleNamespace(recipes=[], total=0)

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    result = await cookidoo_client.search_recipes(TEST_SETTINGS, "sin resultados")
    assert result == {"recipes": [], "total": 0}


@pytest.mark.asyncio
async def test_refresh_y_login_fallidos_lanzan_reauth(monkeypatch):
    class FakeCookidoo:
        def __init__(self, *a, **kw): pass
        on_auth_data_update = None
        def load_token(self, path): pass
        def save_token(self, path): pass
        async def login(self): raise Exception("invalid credentials")
        async def search_recipes(self, query, page=None, **kw):
            raise CookidooAuthException("refresh failed")

    monkeypatch.setattr(cookidoo_client, "_Cookidoo", FakeCookidoo)
    with pytest.raises(cookidoo_client.CookidooReauthRequired):
        await cookidoo_client.search_recipes(TEST_SETTINGS, "salmón")
