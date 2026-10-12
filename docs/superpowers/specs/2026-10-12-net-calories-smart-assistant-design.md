# Calorías netas con ejercicio + asistente más listo

Fecha: 2026-10-12
Estado: aprobada en conversación, pendiente de revisión escrita

## Objetivo

1. El conteo de calorías del día tiene en cuenta lo entrenado: las kcal quemadas en los entrenos registrados (Speediance + HealthKit) suman al restante del día.
2. El asistente (NutriCoach) responde mejor con lo que ya hay: ve las calorías netas, la progresión de fuerza por ejercicio y la adherencia semanal.

## Decisiones tomadas (con el usuario)

- Solo cuentan los **entrenos registrados** (`Workout.caloriesBurned`), no la actividad general de HealthKit (`activeEnergyBurned`). Evita doble conteo con la media de actividad que ya incluye el objetivo (`HealthKitService.fetchDailyCalorieGoal`).
- UI: línea de ejercicio + restante neto. El objetivo base **no cambia**; la barra de progreso sigue usando el objetivo base.
- Asistente: sin nuevas acciones (no registra comidas ni tool-calling). Solo más y mejor contexto.
- Todo se calcula **al vuelo en iOS**, sin persistencia nueva ni cambios de backend.

## Diseño

### 1. `EnergyBalance` (nuevo, `MyFit/Models/EnergyBalance.swift`)

Value type puro + cálculo estático:

```swift
struct EnergyBalance: Equatable {
    var goal: Int           // kcal objetivo base (AppStorage dailyCalorieGoal)
    var consumed: Int       // suma Meal.calories del día
    var exerciseBurned: Int // suma Workout.caloriesBurned del día (nil → 0)
    var netRemaining: Int { goal - consumed + exerciseBurned }

    static func forDay(_ day: Date, meals: [Meal], workouts: [Workout], goal: Int, calendar: Calendar = .current) -> EnergyBalance
}
```

Sin dependencias de SwiftData en los tests (trabaja sobre arrays ya filtrados o los filtra por `day` con el calendar inyectable).

### 2. UI tarjeta "Hoy" (`MyFit/Views/Meals/MealListView.swift`)

- Lee los workouts del día (ya tiene acceso al model context) y calcula `EnergyBalance`.
- Nueva línea bajo las kcal consumidas: `Ejercicio: +350 kcal`, solo visible si `exerciseBurned > 0`.
- El texto de "restante" usa `netRemaining` (rojo si < 0, como hoy).
- La barra de progreso sigue siendo `consumed / goal` (el objetivo no se mueve).

### 3. Progresión de fuerza (`MyFit/Services/StrengthProgression.swift`)

- Entrada: `[Workout]` (con `exercises` cargados).
- Por cada ejercicio (nombre normalizado, case-insensitive) con ≥2 sesiones con peso: última marca vs anterior → línea `Press de pecho: 17,5 → 20 kg/mango (+14%)`.
- "Marca" de una sesión = mejor serie (peso máximo; desempate por reps).
- Salida ordenada por fecha de última sesión, máximo 8 ejercicios.
- Función pura `static func lines(from workouts: [Workout], limit: Int = 8) -> [String]`, testeable sin SwiftData.

### 4. Adherencia semanal (`WeeklyAdherence` en `MyFit/Models/EnergyBalance.swift`)

- Resumen de los últimos 7 días: kcal netas medias, nº de días dentro del ±10% del objetivo, nº de entrenos, proteína media vs objetivo.
- Formato: 3-4 líneas de texto para el prompt.

### 5. Asistente (`MyFit/Services/NutritionChatService.swift`)

- `buildUserDataSection` pasa a usar `EnergyBalance`: sustituye "restante" clásico por balance neto y añade proyección: `Si cenas ~X kcal terminas en objetivo` (X = netRemaining ajustado por lo ya planeado si existe PlannedMeal de cena; si no, netRemaining tal cual).
- Nuevas secciones del system prompt:
  - `PROGRESIÓN DE FUERZA` (líneas de StrengthProgression).
  - `RESUMEN SEMANAL` (adherencia).
- Nueva instrucción en el bloque de rutinas: al proponer pesos, progresar +2,5–5 % sobre la última marca si la sesión previa se completó con esos valores; mantener si falló.
- Las secciones se omiten si están vacías (no ruido en el prompt).

### 6. Reportes (`MyFit/Services/ReportBuilder.swift`)

- El informe semanal usa `EnergyBalance` por día para que las cifras coincidan con la app: media de kcal netas y días en objetivo computan ejercicio.

## Archivos

Nuevos:
- `MyFit/Models/EnergyBalance.swift`
- `MyFit/Services/StrengthProgression.swift`
- `MyFitTests/EnergyBalanceTests.swift`
- `MyFitTests/StrengthProgressionTests.swift`

Modificados:
- `MyFit/Views/Meals/MealListView.swift`
- `MyFit/Services/NutritionChatService.swift`
- `MyFit/Services/ReportBuilder.swift`

Sin cambios en: backend, modelos SwiftData (sin migración), HealthKitService, SyncService.

## Testing

- Swift Testing para `EnergyBalance`: sin entreno (neto = restante clásico), con entreno, workout con `caloriesBurned = nil`, exceso aun con ejercicio.
- Swift Testing para `StrengthProgression`: ejercicio con 1 sesión (no aparece), 2+ sesiones (delta correcto), nombre con distinta capitalización, límite de 8, workouts sin peso.
- Suite existente debe seguir verde: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`.
- Tras crear archivos: `xcodegen generate`.

## Verificación E2E (con el usuario)

1. Día con entreno Speediance importado → la tarjeta Hoy muestra la línea de ejercicio y el restante neto sube.
2. Preguntar al asistente "¿cómo voy hoy?" → menciona lo quemado y proyecta la cena.
3. Pedir rutina de un ejercicio ya entrenado → propone peso progresado respecto a la última sesión.
