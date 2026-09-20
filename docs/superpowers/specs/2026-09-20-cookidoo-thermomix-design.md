# Integración Cookidoo / Thermomix (diseño)

Fecha: 2026-09-20
Estado: pendiente de revisión

## Contexto y objetivo

MyFit ya genera recetas propias con IA (`RecipeGeneratorService`) y tiene un asistente nutricional (`NutritionChatService`). El objetivo es integrar **Cookidoo** (la plataforma oficial de recetas de Thermomix) para que el usuario pueda:

1. **Buscar e importar recetas de Cookidoo** a MyFit (ingredientes, pasos, macros).
2. **Recibir recomendaciones** del asistente basadas en recetas reales de Cookidoo que encajen con sus macros del día.
3. **Planificar recetas** en el calendario semanal de Cookidoo, de modo que aparezcan en su **Thermomix TM6** listas para Cocina Guiada.
4. **Enviar los ingredientes** de una receta a la lista de la compra de Cookidoo.

No existe API oficial pública de Cookidoo. Se usa la librería no oficial [`cookidoo-api`](https://github.com/miaucl/cookidoo-api) (Python, OAuth2 con PKCE), aislada en el backend local propio, igual que ya se hizo con Speediance (ver `2026-09-20-speediance-import-design.md`, cuyo diseño ya reservaba el prefijo `/cookidoo` para esta integración).

## Decisiones tomadas (con el usuario)

1. **Uso personal**: la app no se publica en App Store; se acepta el riesgo de la API no oficial.
2. **Mismo backend local** que Speediance (`backend/` en este repo, FastAPI), accesible por LAN/Tailscale en `http://100.77.65.26:8000`. No se crea un servicio nuevo.
3. **Enfoque "backend tonto + app inteligente"**: el backend es un proxy puro de Cookidoo sin lógica; toda la inteligencia (recomendar según macros, elegir qué proponer) vive en MyFit reutilizando el proveedor de IA configurado en Ajustes.
4. **Alcance v1**: las cuatro funciones (buscar/importar, recomendar por macros, planificar en Cookidoo/TM6, lista de la compra).
5. **UX en dos sitios**: el chat del asistente (descubrir y decidir) y una vista dedicada en la sección Recetas (explorar).
6. El usuario tiene **TM6** y suscripción Cookidoo activa.

## Arquitectura

```
┌─────────────┐   HTTP (LAN/Tailscale)   ┌──────────────────┐   HTTPS    ┌──────────────┐
│   MyFit     │ ───────────────────────► │  backend local    │ ─────────► │   Cookidoo   │
│  (iOS app)  │ ◄─────────────────────── │  (Python/FastAPI) │ ◄───────── │  (OAuth2)    │
└─────────────┘   JSON propio y estable  └──────────────────┘            └──────────────┘
```

Mismo principio que Speediance: la app solo conoce la API propia del backend. La fragilidad de la API no oficial (OAuth, cambios de endpoints, formatos) queda aislada en el backend, donde se arregla sin recompilar la app.

## Componente 1: Backend — router Cookidoo

- **Ubicación**: nuevo router `backend/app/routers/cookidoo.py` (o `backend/app/cookidoo_router.py` según la estructura que deje el trabajo de Speediance) + cliente `backend/app/cookidoo_client.py` envolviendo la librería `cookidoo-api`. Un solo `include_router` en `main.py` para minimizar conflictos con el agente que está implementando Speediance.
- **Dependencia nueva**: `cookidoo-api` en `requirements.txt`.
- **Autenticación Cookidoo**: OAuth2 authorization-code con PKCE.
  - `GET /cookidoo/auth/login` → devuelve (o redirige a) la URL de autorización de Cookidoo; el usuario la abre una vez en el navegador del Mac y completa el login.
  - El backend guarda access/refresh token en un fichero local (permisos 600, fuera del repo, p.ej. `backend/.cookidoo-token.json`, añadido a `.gitignore`) y refresca automáticamente.
  - Si el token es inválido y no se puede refrescar, los endpoints devuelven `401` con cuerpo `{ "error": "reauth_required" }` para que la app muestre "reconecta Cookidoo".
- **Seguridad app→backend**: la misma que ya existe — header `X-API-Key` con el secreto compartido de `.env`.
- **Endpoints** (todos prefijo `/cookidoo`):

| Endpoint | Descripción |
|---|---|
| `GET /cookidoo/recipes/search?q=<texto>&page=<n>` | Lista de recetas: id, título, foto, tiempo total, dificultad, raciones |
| `GET /cookidoo/recipes/{id}` | Detalle: ingredientes con cantidades (agrupados por sección), pasos, y nutrición por ración si Cookidoo la expone |
| `GET /cookidoo/planner/week?date=<ISO>` | Semana planificada (para mostrar qué hay ya en cada día) |
| `POST /cookidoo/planner/add` `{ "recipeId": "...", "date": "2026-09-22" }` | Añade la receta al día indicado; aparece en la TM6 para Cocina Guiada |
| `POST /cookidoo/shopping-list/add-recipe` `{ "recipeId": "..." }` | Añade los ingredientes de la receta a la lista de la compra de Cookidoo |

- **Formato de respuesta** (API propia, estable; ejemplo de búsqueda):

```json
{
  "recipes": [
    {
      "id": "r90756",
      "title": "Salmón al vapor con verduras",
      "imageURL": "https://...",
      "totalMinutes": 35,
      "difficulty": "fácil",
      "servings": 4
    }
  ]
}
```

Detalle (`GET /cookidoo/recipes/{id}`):

```json
{
  "id": "r90756",
  "title": "Salmón al vapor con verduras",
  "imageURL": "https://...",
  "totalMinutes": 35,
  "servings": 4,
  "ingredientSections": [{ "title": null, "items": ["800 g de agua", "4 lomos de salmón", "..."] }],
  "stepSections": [{ "title": null, "items": ["Ponga el agua en el vaso...", "..."] }],
  "nutrition": { "calories": 320, "proteinGrams": 28.0, "carbsGrams": 6.0, "fatGrams": 18.0 }
}
```

`nutrition` puede ser `null` si Cookidoo no expone macros para esa receta — la app los estima entonces por IA (ver Componente 4). **Validación pendiente durante la implementación**: confirmar qué campos de nutrición devuelve realmente `cookidoo-api` y ajustar el contrato antes de dar por cerrado el endpoint.

- **Tests**: pytest con `cookidoo-api` mockeada (patrón de `tests/test_health.py`); cobertura del mapeo a nuestro JSON, del refresh de token y del caso `reauth_required`.

## Componente 2: Modelo de datos (cambio mínimo)

En `MyFit/Models/Recipe.swift`:

- `var cookidooId: String?` — para deduplicación y para las acciones de planner/compra sobre recetas ya importadas.
- `var imageURL: String?` — foto de la receta.
- Las recetas importadas llevan `source = "cookidoo"` (el campo `source` ya existe con valores "nutricionista"/"ia").

Campos opcionales → migración SwiftData trivial. No hay modelos nuevos en SwiftData.

## Componente 3: Cliente en la app

- **Reutilizar `BackendService.swift`** (en construcción por el otro agente para Speediance): base URL y API key de Ajustes/Keychain, errores tipados, protocolo para tests. No se duplica fontanería HTTP.
- Nuevo `CookidooService.swift` en `MyFit/Services/`: struct `Sendable` con DTOs `Decodable` (`CookidooRecipeSummary`, `CookidooRecipeDetail`) y métodos async: `search(query:)`, `recipe(id:)`, `week(containing:)`, `addToPlanner(recipeId:date:)`, `addToShoppingList(recipeId:)`. Mismo patrón de errores en español que `BackendService`/`AIServiceError`.
- **Ajustes**: la sección de backend existente (URL + API key + "Probar conexión") se mantiene única; `GET /health` pasa a devolver también `"cookidoo": "connected" | "error" | "reauth_required"` y la app lo muestra. No hay configuración nueva específica de Cookidoo en la app.

## Componente 4: Recomendación e importación en el chat

Flujo cuando el usuario pide recetas en `NutritionChatView` (p.ej. "cena alta en proteína para la Thermomix"):

1. `NutritionChatService` detecta la intención pidiendo al LLM un JSON estructurado (`{ "action": "search_cookidoo", "query": "..." }`), igual que `RecipeGeneratorService` ya extrae JSON con `AIServicePrompt.extractJSON`.
2. La app ejecuta la búsqueda con `CookidooService` y devuelve al LLM los resultados **junto con los macros restantes del día** (datos que ya tiene la app: comidas del día vs. objetivo del `DietPlan`).
3. El LLM elige 2-3 recetas y explica por qué encajan.
4. El chat pinta **tarjetas de receta** (componente nuevo de vista, reutilizable también en la vista dedicada) con foto, título, tiempo y tres acciones:
   - **Importar** → `GET /cookidoo/recipes/{id}` → si `nutrition` es `null`, estimar con `RecipeGeneratorService.estimateMacros` (marcada como estimada) → crear `Recipe` con `source = "cookidoo"` y `cookidooId`. Si ya existe una receta con ese `cookidooId`, se ofrece abrir la existente en vez de duplicar.
   - **Planificar** → selector de fecha → `POST /cookidoo/planner/add` → confirmación "la verás en tu Thermomix".
   - **A la compra** → `POST /cookidoo/shopping-list/add-recipe` → confirmación.

Si el backend no está accesible, el chat degrada con naturalidad: el asistente avisa de que Cookidoo no está disponible y ofrece generar una receta propia (flujo actual de `RecipeGeneratorService`).

## Componente 5: Vista dedicada en Recetas

- Nueva `CookidooSearchView` accesible desde `RecipeListView` (botón "Buscar en Cookidoo", junto al de generar con IA).
- Buscador de texto + grid de resultados (foto, título, tiempo, dificultad) + vista de detalle con ingredientes, pasos y macros (reales de Cookidoo o estimados por IA, marcados como estimados).
- Las mismas tres acciones de la tarjeta del chat (Importar / Planificar / A la compra), compartiendo el componente.
- Opcional en detalle: ver la semana del planificador (`GET /cookidoo/planner/week`) al elegir fecha, para no pisar una comida ya planificada.

## Manejo de errores

| Situación | Comportamiento |
|---|---|
| Backend apagado / no accesible | Chat degrada a recetas generadas por IA; vista dedicada muestra "backend no accesible" con opción de reintentar |
| Token Cookidoo caducado | El backend refresca solo; si no puede, `401 reauth_required` y la app indica abrir `http://100.77.65.26:8000/cookidoo/auth/login` en el Mac |
| Receta sin macros en Cookidoo | Estimación por IA, marcada como estimada |
| Receta ya importada | Se ofrece abrir la existente (dedup por `cookidooId`) |
| Planificar en fecha pasada u otro error de Cookidoo | Se muestra el error tal cual, sin reintentos silenciosos |
| API de Cookidoo rota por cambio upstream | Se arregla actualizando el backend (librería `cookidoo-api`); la app no cambia |

## Testing

- **Backend** (pytest): mapeo a nuestro JSON con fixtures, refresh de token, `reauth_required`, dedup de parámetros. Librería `cookidoo-api` mockeada; nunca se pega a la cuenta real en tests.
- **App** (Swift Testing / XCTest, patrón de `MyFitTests/`): parsing JSON→DTOs y →`Recipe`; deduplicación por `cookidooId` con contenedor SwiftData en memoria (patrón `MealPersistenceTests`); extracción del JSON de intención del chat; `CookidooService` tras protocolo con stub, sin red.
- **Manual end-to-end** con la cuenta real: buscar → importar → verificar macros → planificar → confirmar que aparece en la TM6 → añadir a la compra y verificarla en la app oficial de Cookidoo.

## Coordinación con el trabajo de Speediance

El backend Speediance está siendo implementado ahora mismo por otro agente. Para evitar conflictos:

- La parte de app de esta integración puede empezar ya sobre el **contrato** de `BackendService` (protocolo + config), sin esperar.
- La parte de backend Cookidoo se implementa **después** de que el otro agente termine `main.py`, o la implementa el propio agente siguiendo este spec. El router Cookidoo toca `main.py` en una sola línea (`include_router`).

## Riesgos conocidos (aceptados por el usuario)

- La API no oficial **viola los términos de Cookidoo**; aceptable para uso personal. Las credenciales/tokens viven solo en el Mac del usuario.
- **Fragilidad upstream**: Vorwerk puede cambiar su API o el flujo OAuth sin aviso. Mitigación: el impacto se limita al backend.
- **Disponibilidad**: todo requiere el Mac encendido y accesible (LAN o Tailscale).
- **Planificar ≠ programar la máquina**: no existe forma de lanzar Cocina Guiada remotamente; añadir al planificador es lo máximo posible — la TM6 muestra la receta del día y el usuario confirma en la pantalla.

## Fuera de alcance (v1)

Crear recetas propias en Cookidoo desde MyFit, gestionar/borrar elementos de la lista de la compra desde MyFit, filtros avanzados de búsqueda (tiempo máximo, dificultad, modelo de TM), sugerencias proactivas sin preguntar al asistente, y auto-arranque del backend como servicio (launchd) — ya apuntado como mejora en el spec de Speediance.
