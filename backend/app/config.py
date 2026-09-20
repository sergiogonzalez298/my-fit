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
