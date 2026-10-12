# Fase 3 — Rutinas por IA subidas a la Gym Monster (diseño)

Fecha: 2026-10-11
Estado: pendiente de revisión

## Contexto y objetivo

La Fase 1 importa los entrenos de Speediance a MyFit con detalle de ejercicios. La Fase 3 cierra el círculo: el usuario pide una rutina al coach en el chat, la IA la propone de forma estructurada, el usuario la revisa y la sube a su Gym Monster 2 como plantilla con un botón.

La viabilidad está validada con un spike en la máquina real del usuario (2026-10-11): una plantilla creada vía API apareció en la app de Speediance y en la Gym Monster 2, y se borró limpiamente.

## Decisiones tomadas (con el usuario)

1. **Solo IA**: no hay constructor manual de rutinas. El coach propone, el usuario aprueba.
2. **En el chat existente** (NutriCoach): la rutina aparece como tarjeta dentro de la conversación, con botón "Subir a la máquina".
3. **Solo subir plantilla**: sin programación en el calendario de Speediance (el endpoint `templateReservation` queda para el futuro).
4. **La IA emite nombres de ejercicio**, no ids: el backend los resuelve contra el catálogo.

## Hallazgos del spike (condicionan el diseño)

- Escritura confirmada en GM2 con `deviceType=1` (el valor por defecto de la librería).
- `POST /api/app/v2/customTrainingTemplate` puede responder `{"code":10,"Parameter error"}` **aun habiendo creado la plantilla**. Regla: tras crear, confirmar SIEMPRE listando plantillas (`list_templates`), y deduplicar por nombre para evitar dobles creaciones en reintentos.
- El `actionLibraryId` correcto se obtiene del detalle de grupo del catálogo (`exercise_group(id).actionLibraryList`), no del id de grupo.
- `delete_template(id)` funciona y no deja residuos.
- La librería (`speediance`, pin `c7fbc4e`) exige `allow_writes=True` para escribir; `create_template` construye payloads seguros (faults documentados: preset_id, alternancia de lados en unilaterales, totalCapacity).

## Arquitectura

```
chat MyFit ──JSON rutina──► tarjeta en app ──POST /speediance/templates──► backend ──► Speediance cloud
     ▲                           │                                            │
     └─ contexto de fuerza ◄── SwiftData (Fase 1)                  resuelve nombres → actionLibraryId
        (NutritionChatService)                                    confirma por listado (quirk code 10)
```

## Componente 1: Backend (2 endpoints nuevos)

Mismo FastAPI, misma auth `X-API-Key`. La escritura se habilita solo aquí (`allow_writes=True` en el cliente de este módulo).

**Resolución de ejercicios bajo demanda (sin endpoint de catálogo)**
- No hay `GET /speediance/exercises` ni precarga de 900 ejercicios: en cada `POST /speediance/templates`, el backend resuelve cada `exerciseName` bajo demanda — 1 petición al listado de grupos (cacheada en memoria de proceso) + 1 petición de detalle por ejercicio nuevo (~8 por rutina), tomando el `actionLibraryId` del primer `actionLibraryList` con `isDisplay=1`.
- Cache incremental en disco (`backend/.cache/exercises.json`): mapea nombre de grupo normalizado → `{actionLibraryId, isLeftRight, isBarbell}`; solo crecen las entradas de ejercicios realmente usados.

**`POST /speediance/templates`**
- Body: `{"name": str, "movements": [{"exerciseName": str, "sets": [{"reps": int, "weightKg": float, "restSeconds": int (opcional, defecto 60)}]}]}`.
- Resolución de nombres contra el catálogo cacheado: coincidencia exacta (case/acentos-insensitive) > prefijo > fuzzy (`difflib`, umbral alto). Los no resueltos devuelven `422` con `{"unmatched": ["..."]}` y no se crea nada.
- Pesos: se envían por punto de carga (por mango), el mismo criterio que la app oficial validado en la Fase 1.
- Creación con la librería (`create_template`), capturando el quirk: si lanza `SpeedianceAPIError` code 10, se lista `list_templates` y se busca por nombre; si está, se considera creada.
- Respuesta: `{"code": str, "name": str, "movementCount": int}` o `422`/`502`.

## Componente 2: Contexto de fuerza para el coach (mini-Fase 2)

`NutritionChatService.buildUserDataSection` se amplía: además de los últimos 3 entrenos (solo tipo/duración), incluirá un **resumen de fuerza reciente** desde SwiftData: por cada uno de los últimos ~5 entrenos con ejercicios, lista de ejercicios con series×reps y peso máximo, para que la IA vea progresión y niveles actuales. Tope de tamaño: los 5 entrenos más recientes con ejercicios, máx. 10 ejercicios por entreno.

## Componente 3: Contrato IA → tarjeta de rutina

El system prompt del coach se amplía con: puede proponer rutinas de entrenamiento cuando el usuario se lo pida; al hacerlo, incluye un bloque JSON con este formato exacto (además de su comentario en texto):

```json
{
  "routine": {
    "name": "Empuje semana 42",
    "movements": [
      {"exerciseName": "Barbell Bench Press",
       "sets": [{"reps": 10, "weightKg": 45, "restSeconds": 90}]}
    ]
  }
}
```

Reglas del prompt: nombres de ejercicio en inglés tal como aparecen en la app de Speediance (la cuenta del usuario tiene el catálogo en inglés), pesos por mango realistas según el historial del usuario, 4-8 ejercicios por rutina.

La app parsea con el patrón existente (`AIServicePrompt.extractJSON`): si hay JSON válido con clave `routine`, la respuesta se muestra como texto (sin el bloque) + tarjeta; si no, se muestra solo el texto — el chat nunca se rompe por un JSON malformado.

## Componente 4: Tarjeta y subida (iOS)

- Nuevo modelo de presentación `RoutineProposal` (struct Codable) y vista `RoutineCardView`: nombre, tabla de ejercicios (nombre, sets×reps, peso, descanso), botón "Subir a la máquina" con estados (idle / subiendo / ✅ subida / ❌ error + reintentar).
- `BackendService` gana `uploadTemplate(_ routine: RoutineProposal) async throws -> UploadResult` (`POST /speediance/templates`). Errores 422 con `unmatched` se muestran en la tarjeta ("No reconozco estos ejercicios: …, díselo al coach").
- Las rutinas propuestas se muestran en el historial del chat (se persisten como parte del `ChatMessageRecord` — el bloque JSON va en el contenido del mensaje y se re-parsea al renderizar).

## Manejo de errores

| Situación | Comportamiento |
|---|---|
| Ejercicio no reconocido por el backend | 422 → tarjeta muestra los nombres no resueltos; no se crea nada |
| API Speediance responde code 10 pero crea | Backend confirma por listado y responde éxito |
| Reintento de subida ya hecha | Backend deduplica por nombre: si ya existe una plantilla con ese nombre, responde éxito con su code (idempotente) |
| Backend caído / sin conexión | Error en la tarjeta con opción de reintentar; la propuesta no se pierde |
| IA emite JSON malformado | Se muestra solo texto, sin tarjeta |
| Catálogo no cacheado aún | La primera subida puede tardar; el cliente iOS usa timeout amplio (600 s) como en la importación |

## Testing

- **Backend** (pytest): resolución de nombres (exacta, sin acentos, prefijo, no encontrada), creación OK, quirk code 10 confirmado por listado, dedup por nombre, 422 con unmatched. Librería `speediance` mockeada.
- **iOS** (Swift Testing): parsing del bloque `routine` (válido, malformado, ausente), `RoutineProposal` Codable, mapping a DTO de upload con stub de `BackendServing`.

## Riesgos conocidos (aceptados)

- La escritura viola los ToS de Speediance igual que la lectura; el usuario lo aceptó en la Fase 1. La plantilla creada es borrable desde la app oficial.
- La API puede cambiar sin aviso; el impacto queda aislado en el backend (actualizar pin de la librería).
- La IA puede inventar nombres de ejercicio inexistentes: mitigado por la resolución server-side con 422 explícito.

## Fuera de alcance

Constructor manual, calendario (`templateReservation`), editar/borrar plantillas desde MyFit, 1RM endpoint, sugerencia automática de rutinas sin petición del usuario, traducción de nombres de ejercicio.
