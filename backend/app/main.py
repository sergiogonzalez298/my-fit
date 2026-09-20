"""API propia y estable del backend local de MyFit."""
from __future__ import annotations

from datetime import date

from fastapi import Depends, FastAPI, Header, HTTPException

from .config import Settings
from .speediance_client import check_speediance, fetch_workouts

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


@app.get("/speediance/workouts", dependencies=[Depends(verify_api_key)])
def speediance_workouts(
    since: date | None = None,
    settings: Settings = Depends(get_settings),
) -> dict:
    try:
        return {"workouts": fetch_workouts(settings, since)}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Error al leer Speediance: {exc}")
