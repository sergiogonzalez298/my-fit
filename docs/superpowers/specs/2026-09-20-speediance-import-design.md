# Fase 1 — Importación de entrenos desde Speediance (diseño)

Fecha: 2026-09-20
Estado: pendiente de revisión

## Contexto y objetivo

MyFit importa hoy entrenos desde Apple HealthKit, pero lo que Speediance escribe en Salud es pobre (tipo, duración, calorías). El objetivo de la Fase 1 es importar a MyFit las sesiones de entrenamiento de Speediance con **detalle de ejercicios agregado** (ejercicios, series, reps, peso), usando la API interna de Speediance a través de un **backend local propio**.

Fases futuras (fuera de alcance, solo se mencionan): Fase 2 — el coach IA usa los datos de fuerza; Fase 3 — subir planes de entrenamiento a la máquina; integración Cookidoo sobre el mismo backend.

## Decisiones tomadas (con el usuario)

1. **Backend local único** en el ordenador del usuario para Speediance (y Cookidoo en el futuro). La app no habla directamente con la API de Speediance.
2. **Detalle agregado**, no por serie: los ejercicios se guardan en el modelo `Exercise` actual (sets × reps × peso). Sin modelo `ExerciseSet`.
3. **Importar todo el historial** en la primera sincronización.
4. La máquina del usuario es una **Gym Monster 2** (relevante solo para la Fase 3; los endpoints de lectura no dependen del tipo de máquina).

## Arquitectura

```
┌─────────────┐   HTTP (LAN/Tailscale)   ┌──────────────────┐   HTTPS   ┌──────────────┐
│   MyFit     │ ───────────────────────► │  backend local    │ ────────► │  Speediance  │
│  (iOS app)  │ ◄─────────────────────── │  (Python/FastAPI) │ ◄──────── │  cloud API   │
└─────────────┘   JSON propio y estable  └──────────────────┘           └──────────────┘
```

Principio clave: la app solo conoce la API propia del backend (estable y bajo nuestro control). Toda la fragilidad de la API no oficial de Speediance (headers congelados, `Versioncode`, re-auth, formatos raros) queda aislada en el backend, donde se arregla sin recompilar la app.

## Componente 1: Backend local (nuevo, directorio `backend/` en el repo)

- **Stack**: Python 3.11+, FastAPI + uvicorn. Cliente Speediance: la librería `speediance` (pookey/speediance-cli, `pip install speediance`), que ya implementa login, headers y parsing.
- **Credenciales Speediance**: email/password en un `.env` local del backend (nunca en el repo, nunca en el iPhone). El backend re-autentica automáticamente cuando el token expira.
- **Endpoints** (prefijo `/speediance` para dejar sitio a `/cookidoo` en el futuro):
  - `GET /health` → `{ "status": "ok", "speediance": "connected" | "error" }` — para el botón "Probar conexión" de la app.
  - `GET /speediance/workouts?since=<ISO8601 opcional>` → lista de sesiones. Sin `since`, devuelve todo el historial.
- **Formato de respuesta** (API propia, estable):

```json
{
  "workouts": [
    {
      "id": "training_id_speediance",
      "title": "Upper Body Strength",
      "date": "2026-09-18T07:30:00Z",
      "durationMinutes": 45,
      "calories": 320,
      "exercises": [
        { "name": "Bench Press", "sets": 4, "reps": 8, "weightKg": 60.0 }
      ]
    }
  ]
}
```

- **Reglas de agregación** (aplicadas en el backend): `sets` = número de series del ejercicio; `reps` = media de reps por serie (redondeada); `weightKg` = peso máximo levantado (los pesos de la API son por punto de carga; dual-handle se suma ×2 para reflejar el peso total movido, igual que hace la app oficial... **pendiente de validar contra datos reales** durante la implementación; si la app oficial muestra por mango, se respeta ese criterio). Sesiones "Free Lift" sin detalle por serie: se importa la sesión sin ejercicios (solo totales), nunca se descarta la sesión entera.
- **Seguridad**: bind a la LAN, header `X-API-Key` con un secreto compartido generado por el usuario (configurado en `.env` y en Ajustes de la app). Suficiente para uso personal en red local / Tailscale.
- **Ejecución**: manual al principio (`uvicorn`); dejar documentado en el README del backend cómo arrancarlo. Un servicio auto-arrancado (launchd) es mejora opcional posterior, fuera de la Fase 1.
- **Tests**: pytest con las respuestas de la librería Speediance mockeadas; cobertura del mapeo a nuestro JSON y de las reglas de agregación.

## Componente 2: Modelo de datos (cambio mínimo)

- Único campo nuevo: `var externalID: String?` en `Workout` (`MyFit/Models/Workout.swift`). Campo opcional → migración SwiftData trivial. No hay modelos nuevos.
- Se rellena con el `id` de Speediance al importar. Los entrenos de HealthKit y manuales lo dejan a `nil`.

## Componente 3: Cliente en la app

- Nuevo `BackendService.swift` en `MyFit/Services/`: struct `Sendable` siguiendo el patrón de los servicios de IA (`URLSession.shared`, DTOs `Decodable`, async/await). Base URL y API key leídas de Ajustes (`@AppStorage` para la URL; la API key en Keychain, cuenta `myfit.backend.apikey`).
- Errores tipados `BackendError: LocalizedError` con mensajes en español (patrón `AIServiceError`): sin conexión con el backend, HTTP con código, respuesta inválida.
- Diseñado tras un protocolo para testear sin red (patrón `StubAIService`).

## Componente 4: Sincronización y deduplicación

- Nuevo `syncSpeediance(context:)` en `SyncService`, llamado desde `syncAll` solo si el backend está configurado. Incremental con `UserDefaults` (`sync.lastSpeediance`); la primera vez se llama sin `since` → todo el historial.
- Deduplicación en dos niveles, por cada sesión recibida:
  1. **Exacta**: si ya existe un `Workout` con ese `externalID` → se omite.
  2. **Por proximidad** (misma ventana de 60 s que ya se usa para HealthKit): si existe un `Workout` en esa ventana (típicamente el que llegó por HealthKit) → **no se crea duplicado**; se enriquece el existente con los ejercicios agregados (solo si aún no tiene ejercicios) y se le asigna el `externalID`.
- Errores en sync automático: silenciados (patrón actual). El usuario tiene la importación manual para ver errores.
- Importación manual: "Importar de Speediance" en el menú de `WorkoutListView`, junto a "Importar de Salud", con alerta de resultado (n importados / error). Patrón de `importFromHealth()`.

## Componente 5: Ajustes

Nueva sección "Speediance" en `SettingsView`, replicando el patrón de proveedores IA:
- Campo URL del backend (ej. `http://192.168.1.50:8000`), campo API key (`SecureField`, Keychain), Guardar/Eliminar.
- Botón **"Probar conexión"** contra `GET /health` con resultado ✅/❌ detallado (incluye si el backend ve Speediance conectado).

## Manejo de errores

| Situación | Comportamiento |
|---|---|
| Backend apagado / no accesible | Sync automático lo ignora silenciosamente; importación manual y "Probar conexión" muestran error claro |
| Credenciales Speediance inválidas | Lo detecta el backend; `/health` devuelve `"speediance": "error"` y la app lo muestra |
| Sesión Free Lift sin detalle | Se importa sin ejercicios |
| Sesión ya importada | Se omite (dedup) |
| API de Speediance rota por cambio upstream | Se arregla actualizando el backend (librería `speediance`); la app no cambia |

## Testing

- **App** (Swift Testing): parsing JSON→`Workout` con fixtures; dedup por `externalID` y enriquecimiento por ventana de 60 s con contenedor SwiftData en memoria (patrón `MealPersistenceTests`); cliente tras protocolo con stub, sin red.
- **Backend** (pytest): reglas de agregación y serialización con datos fixture; librería Speediance mockeada.

## Riesgos conocidos (aceptados por el usuario)

- La API no oficial **viola los ToS de Speediance** (cláusula 5.2); no hay baneos documentados, pero el riesgo contractual existe. Las credenciales viven solo en el ordenador del usuario.
- **Fragilidad upstream**: Speediance está endureciendo su API. Mitigación principal de esta arquitectura: el impacto se limita al backend.
- **Disponibilidad**: la sincronización requiere el ordenador encendido y accesible (LAN o Tailscale).

## Fuera de alcance (Fase 1)

Detalle por serie, puntuaciones de forma, 1RM, coach con datos de fuerza (Fase 2), subir planes a la máquina (Fase 3), Cookidoo (backend preparado para acogerlo), auto-arranque del backend como servicio.
