"""API propia y estable del backend local de MyFit."""
from __future__ import annotations

from datetime import date

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from .config import Settings
from .resolve import resolve_exercises
from .speediance_client import check_speediance, fetch_workouts
from .templates import UnmatchedExercises, upload_template

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


class SetIn(BaseModel):
    reps: int
    weightKg: float
    restSeconds: int = 60


class MovementIn(BaseModel):
    exerciseName: str
    sets: list[SetIn] = Field(min_length=1)


class TemplateIn(BaseModel):
    name: str
    movements: list[MovementIn] = Field(min_length=1)


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


class ResolveIn(BaseModel):
    names: list[str] = Field(min_length=1)


@app.post("/speediance/resolve-exercises", dependencies=[Depends(verify_api_key)])
def resolve_speediance_exercises(
    body: ResolveIn,
    settings: Settings = Depends(get_settings),
) -> dict:
    try:
        return {"exercises": resolve_exercises(settings, body.names)}
    except Exception as exc:
        raise HTTPException(status_code=502,
                            detail=f"Error al resolver ejercicios: {exc}")


from .cookidoo_router import router as cookidoo_router
app.include_router(cookidoo_router)
