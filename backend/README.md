# Backend local de MyFit

Backend mono-usuario (FastAPI) que aisla a la app de las APIs no oficiales de Speediance y Cookidoo.
Usa la librería no oficial `speediance` (la API de Speediance puede cambiar
sin aviso; si algo se rompe, suele bastar `pip install -U speediance`).

## Setup

    cd backend
    python3.11 -m venv .venv
    .venv/bin/pip install -r requirements.txt
    cp .env.example .env   # rellena credenciales y BACKEND_API_KEY

> Nota: la librería `speediance` no está en PyPI; `requirements.txt` la instala pineada a un commit de GitHub. Si Speediance cambia su API, actualiza el pin a un commit más reciente de pookey/speediance-cli.

## Arranque

    .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000

La app se configura en **Ajustes > Speediance** con `http://100.77.65.26:8000` (Tailscale) y la API key, que se envía al backend en el header `X-API-Key`.

> Nota: la app lleva una excepción de App Transport Security (`NSAllowsArbitraryLoads`) para poder hablar HTTP plano con este backend — ATS bloquea incluso los literales IP del rango CGNAT de Tailscale. Recomendada la **IP** de Tailscale en Ajustes; con MagicDNS activo en el iPhone también valdría el hostname.

## Endpoints

- `GET /health` — estado del backend y de los logins de Speediance y Cookidoo.
- `GET /speediance/workouts?since=YYYY-MM-DD` — sesiones con ejercicios
  agregados. Sin `since`, todo el historial (puede tardar minutos: la API
  de Speediance se recorre a 1 petición/segundo). La app usa un timeout de 10 minutos; historiales de más de ~600 sesiones pueden agotarlo en la primera importación. Las fechas de la API llegan en hora local y el backend las convierte a UTC usando la zona horaria del sistema; los pesos son por punto de carga (por mango), igual que muestra la app oficial de Speediance.

- `POST /speediance/templates` — **escritura**: crea una plantilla de entreno
  (aparece en la app de Speediance y en la máquina). Body:
  `{"name": "...", "movements": [{"exerciseName": "...", "sets": [{"reps": 10, "weightKg": 45.0, "restSeconds": 90}]}]}`.
  Los nombres se resuelven contra el catálogo (exacto > prefijo > fuzzy);
  los no reconocidos devuelven 422 con `{"detail": {"unmatched": [...]}}`.
  Idempotente por nombre: subir dos veces la misma rutina no duplica.

Todos requieren el header `X-API-Key`.

- `POST /speediance/resolve-exercises` — resuelve nombres de ejercicio contra el
  catálogo: `{"names": [...]}` → por cada uno, título canónico e imagen oficial
  (`resolved: false` si no se reconoce). Solo lectura; usa el mismo cache
  incremental que la subida de plantillas.

## Tests

    .venv/bin/python -m pytest -v

## Cookidoo

El login OAuth lo hace la librería con `COOKIDOO_EMAIL`/`COOKIDOO_PASSWORD` del `.env`. El token se guarda en `.cookidoo-token.json` (no commiteado) y se refresca solo. Si los endpoints devuelven `reauth_required`, actualiza las credenciales del `.env` y borra `.cookidoo-token.json`.
