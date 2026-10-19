"""Acceso a Cookidoo a través de la librería no oficial `cookidoo-api`.

La librería resuelve el flujo OAuth2 (authorization-code + PKCE, cliente público
de la app móvil) a partir del email/password del .env. El token se persiste en
backend/.cookidoo-token.json y la librería lo refresca sola; el callback
`on_auth_data_update` mantiene el fichero en sync tras cada login/refresh.
"""
from __future__ import annotations

import html
import os
import re
from datetime import date
from pathlib import Path

import aiohttp
from cookidoo_api import Cookidoo as _Cookidoo
from cookidoo_api.exceptions import CookidooAuthException
from cookidoo_api.types import CookidooConfig, CookidooLocalizationConfig

from .config import Settings

_TOKEN_PATH = Path(__file__).resolve().parent.parent / ".cookidoo-token.json"


def _save_token(client, path):
    """Persiste el token y lo deja con permisos 600 (solo el usuario)."""
    client.save_token(str(path))
    os.chmod(path, 0o600)


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
        client.on_auth_data_update = lambda _auth: _save_token(client, _TOKEN_PATH)
        try:
            client.load_token(str(_TOKEN_PATH))
        except Exception:
            try:
                await client.login()
            except Exception as exc:
                raise CookidooReauthRequired(str(exc)) from exc
        try:
            return await fn(client)
        except CookidooAuthException:
            try:
                await client.login()
            except Exception as exc:
                raise CookidooReauthRequired(str(exc)) from exc
            try:
                return await fn(client)
            except CookidooAuthException as exc:
                raise CookidooReauthRequired(str(exc)) from exc


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
