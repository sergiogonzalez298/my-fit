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


def _upstream_error(exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=502,
        content={"error": "cookidoo_error", "detail": str(exc)},
    )


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
        return _upstream_error(exc)


@router.get("/recipes/{recipe_id}", dependencies=[Depends(require_api_key)])
async def details(recipe_id: str, settings: Settings = Depends(get_settings)):
    try:
        return await cookidoo_client.recipe_details(settings, recipe_id)
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        return _upstream_error(exc)


@router.get("/planner/week", dependencies=[Depends(require_api_key)])
async def week(date: date, settings: Settings = Depends(get_settings)):
    try:
        return await cookidoo_client.calendar_week(settings, date)
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        return _upstream_error(exc)


@router.post("/planner/add", dependencies=[Depends(require_api_key)])
async def planner_add(body: PlannerAddBody, settings: Settings = Depends(get_settings)):
    try:
        await cookidoo_client.add_recipe_to_calendar(settings, body.recipeId, body.date)
        return {"ok": True}
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        return _upstream_error(exc)


@router.post("/shopping-list/add-recipe", dependencies=[Depends(require_api_key)])
async def shopping_add(body: ShoppingAddBody, settings: Settings = Depends(get_settings)):
    try:
        n = await cookidoo_client.add_recipe_to_shopping_list(settings, body.recipeId)
        return {"ok": True, "ingredientsAdded": n}
    except cookidoo_client.CookidooReauthRequired:
        return _reauth_response()
    except Exception as exc:
        return _upstream_error(exc)
