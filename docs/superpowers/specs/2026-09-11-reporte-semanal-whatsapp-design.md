# Reporte de progreso para el nutricionista, por WhatsApp

Fecha: 2026-09-11
Estado: aprobado, pendiente de plan de implementación

## Problema

Hoy no hay forma de resumir el progreso (peso, entrenos, macros) para compartirlo con el nutricionista. Toca mirar cada pestaña por separado y redactar el mensaje a mano cada semana.

Se necesita una pantalla nueva que agregue los datos ya existentes de un periodo (`WeightEntry`, `Workout`, `Meal`) en un texto listo para enviar por WhatsApp, y que guarde un historial de lo que se ha ido enviando.

## Decisiones de producto

| Decisión | Elección |
|---|---|
| Periodo | Rango de fechas libre (no una semana fija), con un selector "Desde" / "Hasta" |
| Persistencia | Snapshot guardado al generar: registro inmutable de lo que se envió, no recalculado en cada visita |
| Envío | Manual: deep link de WhatsApp con el texto ya redactado; el usuario elige el contacto y pulsa enviar |
| Automatización | Ninguna. Sin notificaciones ni generación en segundo plano; el usuario abre la pestaña cuando quiere |
| Entrenos en el texto | Resumen agregado (nº de sesiones, minutos totales, calorías quemadas) — sin desglose por ejercicio |
| Peso en el texto | Inicio, fin y variación del rango — no cada pesada |
| Macros en el texto | Media diaria del rango comparada con el objetivo guardado en Ajustes |
| Ubicación | Nueva pestaña "Reportes" en `ContentView` |

## Arquitectura

### Modelo de datos

Un tipo nuevo en `MyFit/Models/`:

```swift
@Model
final class ReportSnapshot {
    var rangeStart: Date     // startOfDay, inclusive
    var rangeEnd: Date       // startOfDay, inclusive
    var createdAt: Date
    var reportText: String   // texto exacto compartido por WhatsApp

    var weightStartKg: Double?
    var weightEndKg: Double?

    var workoutCount: Int
    var totalDurationMinutes: Int
    var caloriesBurned: Int

    var avgKcal: Double
    var avgProtein: Double
    var avgCarbs: Double
    var avgFat: Double
    var kcalGoal: Int
    var proteinGoal: Int
    var carbsGoal: Int
    var fatGoal: Int
    var daysLogged: Int      // días del rango con ≥1 comida registrada
    var totalDays: Int       // rangeEnd - rangeStart + 1
}
```

`reportText` se guarda literal: es el registro de lo que de verdad se mandó, aunque más tarde cambie el formato de texto o los datos de origen. Los campos numéricos se guardan aparte para poder listar el historial sin re-parsear el string.

Se añade a los `modelContainer` de `MyFitApp.swift` y del `#Preview` de `ContentView.swift`, junto al resto de modelos.

### Servicio

`ReportBuilder` (nuevo, en `MyFit/Services/`), sin estado, sin red:

```swift
enum ReportBuilder {
    /// Agrega los datos del rango y devuelve un snapshot listo para guardar.
    /// No inserta nada en el contexto: eso lo decide quien lo llama.
    static func build(from rangeStart: Date, to rangeEnd: Date,
                       context: ModelContext) -> ReportSnapshot

    /// Redacta el texto para WhatsApp a partir de los campos agregados.
    static func formatText(_ snapshot: ReportSnapshot) -> String
}
```

`build` consulta:
- `WeightEntry` con `day` en `[rangeStart, rangeEnd]`, ordenadas por fecha → `weightStartKg`/`weightEndKg` de la primera y la última (nil si no hay ninguna).
- `Workout` con `date` en el rango → cuenta, suma de `durationMinutes`, suma de `caloriesBurned` (tratando nil como 0).
- `Meal` con `date` en el rango, agrupadas por día → `daysLogged` = nº de días distintos con al menos una comida; medias de kcal/proteína/carbos/grasa = suma de esos días dividida entre `daysLogged` (0 si `daysLogged == 0`, sin dividir por cero).
- Objetivos desde `UserDefaults` (`dailyCalorieGoal`, `dailyProteinGoal`, `dailyCarbsGoal`, `dailyFatGoal`, ya usados por `NutritionChatService`).

`formatText` produce algo así (en español, con emojis, pensado para pegarse en un chat):

```
📋 Reporte (9 sep - 15 sep)

⚖️ Peso: 82.4 kg → 81.9 kg (-0.5 kg)

💪 Entrenos: 4 sesiones · 3h 20min · ~1200 kcal quemadas

🍽️ Macros (media diaria, 6/7 días registrados):
 · Kcal: 2100 / 2300
 · Proteína: 145 / 160 g
 · Carbos: 210 / 220 g
 · Grasa: 65 / 70 g
```

Cuando falta un dato (sin pesadas, sin entrenos, objetivo en 0) esa línea cambia de forma — ver Casos límite.

### UI

**`ReportsView`** (nueva, `MyFit/Views/Reports/`) — pantalla de la nueva pestaña:
- Lista del historial (`@Query` de `ReportSnapshot`, orden `createdAt` descendente): cada fila muestra el rango de fechas y cuándo se generó.
- Botón "Nuevo reporte" que abre `NewReportView`.
- Tocar una fila abre `ReportDetailView` con ese snapshot.

**`NewReportView`** (nueva, sheet) — dos `DatePicker` ("Desde" / "Hasta", por defecto los últimos 7 días) y, debajo, una vista previa en vivo: en cada cambio de fecha llama a `ReportBuilder.build` (sin guardar) y muestra el texto resultante. Botón "Generar y enviar":
1. Inserta el `ReportSnapshot` en el contexto.
2. Abre WhatsApp (ver "Envío" más abajo) con `reportText`.

Validación: "Generar y enviar" deshabilitado si `rangeEnd < rangeStart`. Si el rango supera 31 días, un texto de aviso bajo los selectores ("el texto puede quedar muy largo") — no bloquea.

**`ReportDetailView`** (nueva) — muestra `reportText` de un snapshot guardado, de solo lectura, con fecha de creación. Dos acciones:
- "Reenviar": reabre WhatsApp con el `reportText` guardado, tal cual, sin recalcular.
- "Editar y regenerar" (requiere confirmación): reabre `NewReportView` precargada con `rangeStart`/`rangeEnd` de este snapshot; al generar, sobrescribe los campos de este mismo registro en vez de crear uno nuevo.

**`ContentView`** — se añade la sexta pestaña:
```swift
ReportsView()
    .tabItem { Label("Reportes", systemImage: "square.and.arrow.up.on.square") }
    .tag(5)
```

### Envío por WhatsApp

Deep link `whatsapp://send?text=<reportText URL-encoded>`:
- Si `UIApplication.shared.canOpenURL` es `true` (WhatsApp instalado) y el texto no es descomunal, se abre ese link: WhatsApp arranca con el texto ya escrito y el usuario elige el contacto.
- Si no (WhatsApp no instalado, o `canOpenURL` falla), se usa `ShareLink` con el mismo `reportText`: hoja de compartir estándar de iOS, para elegir otra app o copiar el texto. Es un fallback silencioso, no un error.

## Flujo de datos

```
NewReportView (Desde/Hasta)
        │  cada cambio de fecha
        ▼
ReportBuilder.build(rangeStart, rangeEnd, context)
        │
        ▼
ReportSnapshot (en memoria, sin guardar)  ──►  vista previa (formatText)
        │
   [Generar y enviar]
        │
        ▼
context.insert(snapshot)               ──►  historial en ReportsView
        │
        ▼
whatsapp://send?text=…  (o ShareLink si no hay WhatsApp)
```

`ReportDetailView` → "Reenviar" salta directo al último paso con el `reportText` ya guardado, sin pasar por `build` de nuevo.

## Casos límite

- **Sin datos en todo el rango** (ni pesos, ni entrenos, ni comidas): no es un error. El texto muestra "Sin registros de peso" / "Sin entrenos" según toque, y las macros en 0 con "0/7 días registrados".
- **Solo algunos días con comidas**: la media se calcula sobre `daysLogged`, no sobre `totalDays`, y el texto lo deja explícito ("media diaria, 5/7 días registrados") para que no se lea como si fuera la media real de los 7 días.
- **Objetivo de macros no configurado** (valor en 0 en `UserDefaults`): esa línea se muestra sin el "/objetivo" (`Kcal: 2100` en vez de `2100/2300`).
- **Una sola pesada en el rango**: `weightStartKg == weightEndKg`, variación 0 — se muestra igual, sin caso especial.
- **WhatsApp no instalado**: fallback automático a `ShareLink`, sin alerta de error.
- **Texto muy largo** (rango largo, muchos entrenos con notas — aunque las notas de `Workout` no entran en el texto): si supera un umbral prudente de caracteres, se usa `ShareLink` directamente en vez del deep link, que sí tiene límite práctico de longitud.
- **Rango inválido** (hasta < desde): cubierto por la validación del formulario; el botón queda deshabilitado, no hace falta manejarlo en el builder.
- **"Editar y regenerar" sobre un snapshot ya reenviado varias veces**: se sobrescribe igual; el historial no guarda versiones intermedias, solo el estado actual de ese snapshot.

## Testing

- **`ReportBuilderTests`** (Swift Testing, `ModelContext` en memoria con datos sembrados):
  - Peso: una sola pesada en el rango → delta 0; ninguna pesada → ambos campos `nil`.
  - Entrenos: cuenta, duración y calorías correctas sumando sesiones dentro y fuera del rango (las de fuera no cuentan).
  - Macros: media sobre `daysLogged`, no sobre `totalDays`; caso `daysLogged == 0` no divide por cero.
  - `totalDays` incluye ambos extremos del rango.
- **`formatText`**: dado un `ReportSnapshot` con valores conocidos, el texto generado es el esperado, incluidos los casos sin pesadas / sin objetivo / cero entrenos.
- **Persistencia**: generar inserta un `ReportSnapshot`; "editar y regenerar" actualiza el mismo registro (mismo identity), no crea uno duplicado.
- **Manual en simulador**: crear reportes con rangos distintos, comprobar que sin WhatsApp instalado cae al `ShareLink`, y que el texto se pega bien en una conversación real de WhatsApp (emojis, saltos de línea).

## Fuera de alcance

- Envío automático o programado (recordatorios, notificaciones).
- Elegir o guardar el contacto del nutricionista dentro de la app — lo elige el usuario en WhatsApp al enviar.
- Desglose por ejercicio o por comida dentro del texto del reporte.
- Editar el `reportText` a mano antes de enviar (solo se puede regenerar completo).
- Exportar a PDF o cualquier formato que no sea texto plano.
