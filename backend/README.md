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
> Nota: la app lleva una excepción de App Transport Security (`NSAllowsArbitraryLoads`) para poder hablar HTTP plano con este backend — ATS bloquea incluso los literales IP del rango CGNAT de Tailscale. Recomendada la **IP** de Tailscale en Ajustes; con MagicDNS activo en el iPhone también valdría el hostname.

## Endpoints

- `GET /health` — estado del backend y del login de Speediance.
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

## Tests

    .venv/bin/python -m pytest tests/ -v
