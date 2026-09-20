# MyFit Backend

Backend local que expone los entrenos de Speediance a la app MyFit.
Usa la librería no oficial `speediance` (la API de Speediance puede cambiar
sin aviso; si algo se rompe, suele bastar `pip install -U speediance`).

## Arranque

    cd backend
    python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
    cp .env.example .env   # rellena credenciales Speediance y BACKEND_API_KEY
    .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

> Nota: la librería `speediance` no está en PyPI; `requirements.txt` la instala pineada a un commit de GitHub. Si Speediance cambia su API, actualiza el pin a un commit más reciente de pookey/speediance-cli.

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
