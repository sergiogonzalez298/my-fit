# Calorías netas + asistente con más contexto — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el conteo de calorías del día descuente lo entrenado (restante neto) y que el asistente vea balance neto, progresión de fuerza y adherencia semanal.

**Architecture:** Cálculo puro al vuelo en iOS: dos unidades nuevas sin estado (`EnergyBalance`+`WeeklyAdherence`, `StrengthProgression`) consumidas por la tarjeta Hoy, el system prompt del asistente y el reporte semanal. Sin cambios de backend ni de esquema SwiftData.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-12-net-calories-smart-assistant-design.md`

## Global Constraints

- Tras crear cualquier archivo `.swift` nuevo: `xcodegen generate` antes de compilar/testar.
- Tests: Swift Testing (`@Suite`/`@Test`/`#expect`), estilo de `MyFitTests/MacrosTests.swift`.
- Comando de test por suite: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/<Suite> -quiet 2>&1 | tail -20`. Exit 0 = verde; ignorar la línea de ruido "error: the following command failed with exit code 0" si aparece.
- Suite completa: mismo comando sin `-only-testing`.
- Los modelos `@Model` (`Meal`, `Workout`, `Exercise`) se pueden instanciar en tests sin `ModelContext`: son objetos normales hasta que se insertan.
- Pesos en kg POR MANGO (convención Speediance) en todos los textos.
- Textos de UI y prompt en español; decimales con `String(format: "%g", ...)` (punto POSIX), como hace `formatStrengthContext`.
- No modificar `HealthKitService`, `SyncService` ni el backend.

## Review Focus

1. Entreno duplicado (Speediance + HealthKit a la vez, dedup fallida) sumaría sus kcal dos veces — comportamiento esperado: reflejar lo almacenado; la dedup es responsabilidad del importador. Test en Task 1 (`duplicatesSum`).
2. Ejercicio con nombre distinto entre sesiones (sesiones antiguas en chino vs inglés) → no debe mezclarlos ni romper; simplemente no hay línea de progresión para ese nombre. Test en Task 3 (`namesDontMix`).
3. `weightKg` 0 o nil (la máquina registra 0 al inicio) → ignorado en la progresión. Test en Task 3 (`zeroAndNilWeightIgnored`).
4. Objetivos a 0 (usuario sin configurar) → adherencia sin líneas de objetivo ni proteína, sin crashes. Test en Task 2 (`noGoal`).
5. Día con entreno pero sin comidas → NO cuenta como "día registrado" en las medias (consistente con `ReportBuilder.daysLogged`). Test en Task 2 (`workoutOnlyDayIgnored`).

---

### Task 1: `EnergyBalance` (balance neto del día)

**Files:**
- Create: `MyFit/Models/EnergyBalance.swift`
- Test: `MyFitTests/EnergyBalanceTests.swift`

**Interfaces:**
- Consumes: `Meal.date/.calories`, `Workout.date/.caloriesBurned` (modelos existentes).
- Produces:
  ```swift
  struct EnergyBalance: Equatable {
      var goal: Int
      var consumed: Int
      var exerciseBurned: Int
      var netRemaining: Int { get } // goal - consumed + exerciseBurned
      static func forDay(_ day: Date, meals: [Meal], workouts: [Workout], goal: Int, calendar: Calendar = .current) -> EnergyBalance
  }
  ```
  Usado por Tasks 4, 5 y 6.

- [ ] **Step 1: Write the failing test**

Crear `MyFitTests/EnergyBalanceTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("EnergyBalance")
struct EnergyBalanceTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func meal(_ offset: Int, kcal: Int) -> Meal {
        Meal(date: day(offset), name: "x", calories: kcal,
             proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
    }

    @Test("sin entrenos el neto es el restante clásico")
    func noWorkouts() {
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 500), meal(0, 300)],
                                           workouts: [], goal: 2000)
        #expect(balance.consumed == 800)
        #expect(balance.exerciseBurned == 0)
        #expect(balance.netRemaining == 1200)
    }

    @Test("el ejercicio suma al restante")
    func withWorkout() {
        let workout = Workout(date: Date(), caloriesBurned: 350)
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 800)],
                                           workouts: [workout], goal: 2000)
        #expect(balance.exerciseBurned == 350)
        #expect(balance.netRemaining == 1550)
    }

    @Test("workout sin calorías cuenta 0")
    func nilCalories() {
        let balance = EnergyBalance.forDay(Date(), meals: [],
                                           workouts: [Workout(date: Date())], goal: 2000)
        #expect(balance.exerciseBurned == 0)
    }

    @Test("exceso aun entrenando da neto negativo")
    func overEating() {
        let w = Workout(date: Date(), caloriesBurned: 100)
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 2500)], workouts: [w], goal: 2000)
        #expect(balance.netRemaining == -400)
    }

    @Test("solo cuenta lo del día pedido")
    func filtersByDay() {
        let balance = EnergyBalance.forDay(Date(), meals: [meal(0, 500), meal(-1, 900)],
                                           workouts: [Workout(date: day(-1), caloriesBurned: 300)],
                                           goal: 2000)
        #expect(balance.consumed == 500)
        #expect(balance.exerciseBurned == 0)
    }

    @Test("dos registros del mismo entreno suman doble — la dedup es del importador")
    func duplicatesSum() {
        let a = Workout(date: Date(), caloriesBurned: 300)
        let b = Workout(date: Date(), caloriesBurned: 300)
        let balance = EnergyBalance.forDay(Date(), meals: [], workouts: [a, b], goal: 2000)
        #expect(balance.exerciseBurned == 600)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/EnergyBalanceTests -quiet 2>&1 | tail -20`
Expected: FAIL de compilación ("cannot find 'EnergyBalance' in scope").

- [ ] **Step 3: Write minimal implementation**

Crear `MyFit/Models/EnergyBalance.swift`:

```swift
import Foundation

/// Balance calórico de un día: lo comido, lo quemado entrenando y lo que queda.
/// Solo cuenta entrenos registrados (Speediance/HealthKit), no la actividad general,
/// para no duplicar la media de actividad que ya incluye el objetivo.
struct EnergyBalance: Equatable {
    var goal: Int
    var consumed: Int
    var exerciseBurned: Int

    /// Restante sumando el ejercicio. Puede ser negativo: exceso aun entrenando.
    var netRemaining: Int { goal - consumed + exerciseBurned }

    static func forDay(_ day: Date, meals: [Meal], workouts: [Workout], goal: Int,
                       calendar: Calendar = .current) -> EnergyBalance {
        let start = calendar.startOfDay(for: day)
        let consumed = meals
            .filter { calendar.startOfDay(for: $0.date) == start }
            .map(\.calories).reduce(0, +)
        let burned = workouts
            .filter { calendar.startOfDay(for: $0.date) == start }
            .map { $0.caloriesBurned ?? 0 }.reduce(0, +)
        return EnergyBalance(goal: goal, consumed: consumed, exerciseBurned: burned)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/EnergyBalanceTests -quiet 2>&1 | tail -20`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add MyFit/Models/EnergyBalance.swift MyFitTests/EnergyBalanceTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: EnergyBalance — balance neto del día con ejercicio"
```

---

### Task 2: `WeeklyAdherence` (resumen de 7 días para el prompt)

**Files:**
- Modify: `MyFit/Models/EnergyBalance.swift` (añadir el enum al final)
- Test: `MyFitTests/WeeklyAdherenceTests.swift` (crear)

**Interfaces:**
- Consumes: `Meal.date/.calories/.proteinGrams`, `Workout.date/.caloriesBurned`.
- Produces:
  ```swift
  enum WeeklyAdherence {
      static func lines(today: Date = Date(), meals: [Meal], workouts: [Workout],
                        kcalGoal: Int, proteinGoal: Int,
                        calendar: Calendar = .current) -> [String]
  }
  ```
  Devuelve 0-4 líneas en español listas para el prompt. Vacío si no hay ningún día con comidas en los últimos 7 (incl. hoy). Usado por Task 5.

- [ ] **Step 1: Write the failing test**

Crear `MyFitTests/WeeklyAdherenceTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("WeeklyAdherence")
struct WeeklyAdherenceTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func meal(_ offset: Int, kcal: Int, protein: Double = 0) -> Meal {
        Meal(date: day(offset), name: "x", calories: kcal,
             proteinGrams: protein, carbsGrams: 0, fatGrams: 0)
    }

    @Test("sin comidas registradas no hay líneas")
    func empty() {
        #expect(WeeklyAdherence.lines(meals: [], workouts: [],
                                      kcalGoal: 2000, proteinGoal: 150).isEmpty)
    }

    @Test("media neta descuenta ejercicio y cuenta días en objetivo ±10%")
    func netAverage() {
        // netas: 1900 (2200-300), 2000, 2500 → media 2133; en objetivo (1800-2200): los dos primeros
        let meals = [meal(-2, 2200), meal(-1, 2000), meal(0, 2500)]
        let workouts = [Workout(date: day(-2), caloriesBurned: 300)]
        let lines = WeeklyAdherence.lines(meals: meals, workouts: workouts,
                                          kcalGoal: 2000, proteinGoal: 150)
        #expect(lines.contains { $0.contains("2133 kcal netas") })
        #expect(lines.contains { $0.contains("2 de 3 días") })
        #expect(lines.contains { $0.contains("Entrenos en los últimos 7 días: 1") })
    }

    @Test("día con ejercicio pero sin comida no es día registrado")
    func workoutOnlyDayIgnored() {
        let lines = WeeklyAdherence.lines(meals: [meal(0, 2000)],
                                          workouts: [Workout(date: day(-1), caloriesBurned: 400)],
                                          kcalGoal: 2000, proteinGoal: 150)
        #expect(lines.contains { $0.contains("1 de 1 días") })
        #expect(lines.contains { $0.contains("Entrenos en los últimos 7 días: 1") })
    }

    @Test("sin objetivo configurado no hay líneas de objetivo ni proteína")
    func noGoal() {
        let lines = WeeklyAdherence.lines(meals: [meal(0, 1800, protein: 120)], workouts: [],
                                          kcalGoal: 0, proteinGoal: 0)
        #expect(lines.contains { $0.contains("1800 kcal netas") })
        #expect(!lines.contains { $0.contains("objetivo") })
        #expect(!lines.contains { $0.contains("Proteína") })
    }

    @Test("la ventana es de 7 días incluyendo hoy")
    func windowIsSevenDays() {
        // día -7 queda fuera; si entrara, la media sería (2000+1000)/2 = 1500
        let lines = WeeklyAdherence.lines(meals: [meal(0, 2000), meal(-7, 1000)], workouts: [],
                                          kcalGoal: 2000, proteinGoal: 150)
        #expect(lines.contains { $0.contains("2000 kcal netas") })
        #expect(lines.contains { $0.contains("de 1 días") })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/WeeklyAdherenceTests -quiet 2>&1 | tail -20`
Expected: FAIL de compilación ("cannot find 'WeeklyAdherence' in scope").

- [ ] **Step 3: Write minimal implementation**

Añadir al final de `MyFit/Models/EnergyBalance.swift`:

```swift
/// Resumen de adherencia de los últimos 7 días (incl. hoy) para el prompt del asistente.
/// Un día solo cuenta como "registrado" si tiene comidas — igual que `ReportBuilder.daysLogged`.
enum WeeklyAdherence {
    static func lines(today: Date = Date(), meals: [Meal], workouts: [Workout],
                      kcalGoal: Int, proteinGoal: Int,
                      calendar: Calendar = .current) -> [String] {
        let startToday = calendar.startOfDay(for: today)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: startToday) else {
            return []
        }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }

        var netByDay: [Date: Int] = [:]
        var proteinByDay: [Date: Double] = [:]
        var workoutsCount = 0
        for day in days {
            let dayWorkouts = workouts.filter { calendar.startOfDay(for: $0.date) == day }
            workoutsCount += dayWorkouts.count
            let dayMeals = meals.filter { calendar.startOfDay(for: $0.date) == day }
            guard !dayMeals.isEmpty else { continue }
            let burned = dayWorkouts.map { $0.caloriesBurned ?? 0 }.reduce(0, +)
            netByDay[day] = dayMeals.map(\.calories).reduce(0, +) - burned
            proteinByDay[day] = dayMeals.map(\.proteinGrams).reduce(0, +)
        }
        guard !netByDay.isEmpty else { return [] }

        let logged = netByDay.count
        let avgNet = netByDay.values.reduce(0, +) / logged
        let avgProtein = Int(proteinByDay.values.reduce(0, +) / Double(logged))

        var lines: [String] = []
        if kcalGoal > 0 {
            let low = Int(Double(kcalGoal) * 0.9)
            let high = Int(Double(kcalGoal) * 1.1)
            let inGoal = netByDay.values.filter { $0 >= low && $0 <= high }.count
            lines.append("Media de los últimos 7 días: \(avgNet) kcal netas/día (objetivo \(kcalGoal), ejercicio ya descontado).")
            lines.append("Días en objetivo (±10%): \(inGoal) de \(logged) días registrados.")
        } else {
            lines.append("Media de los últimos 7 días: \(avgNet) kcal netas/día.")
        }
        lines.append("Entrenos en los últimos 7 días: \(workoutsCount).")
        if proteinGoal > 0 {
            lines.append("Proteína media: \(avgProtein) g/día (objetivo \(proteinGoal) g).")
        }
        return lines
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/WeeklyAdherenceTests -quiet 2>&1 | tail -20`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add MyFit/Models/EnergyBalance.swift MyFitTests/WeeklyAdherenceTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: WeeklyAdherence — resumen de 7 días con kcal netas"
```

---

### Task 3: `StrengthProgression` (última marca vs anterior por ejercicio)

**Files:**
- Create: `MyFit/Services/StrengthProgression.swift`
- Test: `MyFitTests/StrengthProgressionTests.swift`

**Interfaces:**
- Consumes: `Workout.date/.exercises`, `Exercise.name/.reps/.weightKg`.
- Produces:
  ```swift
  enum StrengthProgression {
      static func lines(from workouts: [Workout], limit: Int = 8) -> [String]
  }
  ```
  Una línea por ejercicio con ≥2 sesiones con peso: `"Press banca: 17.5 → 20 kg/mango (+14%)"`. Ordenadas por fecha de la última sesión, más reciente primero. Usado por Task 5.

- [ ] **Step 1: Write the failing test**

Crear `MyFitTests/StrengthProgressionTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("StrengthProgression")
struct StrengthProgressionTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    private func ex(_ name: String, _ kg: Double?) -> Exercise {
        Exercise(name: name, sets: 3, reps: 10, weightKg: kg)
    }

    private func workout(_ offset: Int, _ exercises: [Exercise]) -> Workout {
        Workout(date: day(offset), exercises: exercises)
    }

    @Test("una sola sesión no muestra línea")
    func singleSessionHidden() {
        let lines = StrengthProgression.lines(from: [workout(0, [ex("Press", 20)])])
        #expect(lines.isEmpty)
    }

    @Test("subida calcula el porcentaje")
    func increase() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("Press banca", 17.5)]),
            workout(0, [ex("Press banca", 20)]),
        ])
        #expect(lines == ["Press banca: 17.5 → 20 kg/mango (+14%)"])
    }

    @Test("mismo peso dice sin cambio")
    func noChange() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("Sentadilla", 30)]),
            workout(0, [ex("Sentadilla", 30)]),
        ])
        #expect(lines == ["Sentadilla: 30 → 30 kg/mango (sin cambio)"])
    }

    @Test("el nombre ignora mayúsculas y espacios")
    func caseInsensitive() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("press banca", 17.5)]),
            workout(0, [ex("Press Banca ", 20)]),
        ])
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("Press Banca: "))
    }

    @Test("peso nil o 0 se ignora")
    func zeroAndNilWeightIgnored() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("Curl", nil)]),
            workout(0, [ex("Curl", 0)]),
        ])
        #expect(lines.isEmpty)
    }

    @Test("nombres distintos no se mezclan (sesiones antiguas en otro idioma)")
    func namesDontMix() {
        let lines = StrengthProgression.lines(from: [
            workout(-7, [ex("卧推", 17.5)]),
            workout(0, [ex("Bench Press", 20)]),
        ])
        #expect(lines.isEmpty)
    }

    @Test("la marca de una sesión es su mejor serie y solo compara las 2 últimas")
    func bestSetPerSession() {
        let lines = StrengthProgression.lines(from: [
            workout(-14, [ex("Press", 10)]),
            workout(-7, [ex("Press", 15), ex("Press", 17.5)]),
            workout(0, [ex("Press", 20)]),
        ])
        #expect(lines == ["Press: 17.5 → 20 kg/mango (+14%)"])
    }

    @Test("máximo 8 líneas")
    func limit() {
        var workouts: [Workout] = []
        for i in 0..<9 {
            workouts.append(workout(-7, [ex("Ej\(i)", 10)]))
            workouts.append(workout(0, [ex("Ej\(i)", 12)]))
        }
        #expect(StrengthProgression.lines(from: workouts).count == 8)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/StrengthProgressionTests -quiet 2>&1 | tail -20`
Expected: FAIL de compilación ("cannot find 'StrengthProgression' in scope").

- [ ] **Step 3: Write minimal implementation**

Crear `MyFit/Services/StrengthProgression.swift`:

```swift
import Foundation

/// Comparativa de la última marca de cada ejercicio con la de la sesión anterior.
/// Pesos por mango (convención Speediance). Función pura: testeable sin SwiftData.
enum StrengthProgression {

    private struct Mark {
        let date: Date
        let weightKg: Double
        let reps: Int
        let displayName: String
    }

    /// Una línea por ejercicio con ≥2 sesiones con peso: "Press banca: 17.5 → 20 kg/mango (+14%)".
    /// Ordenadas por fecha de la última sesión (más reciente primero), máximo `limit`.
    static func lines(from workouts: [Workout], limit: Int = 8) -> [String] {
        // Agrupa por nombre normalizado; la marca de una sesión es su mejor serie
        // (peso máximo, desempate por reps). El nombre mostrado es el de la sesión
        // MÁS RECIENTE (las antiguas pueden venir en otro idioma).
        var marksByKey: [String: [Mark]] = [:]
        for workout in workouts {
            var bestInSession: [String: Mark] = [:]
            for exercise in workout.exercises {
                guard let weight = exercise.weightKg, weight > 0 else { continue }
                let key = exercise.name.trimmingCharacters(in: .whitespaces).lowercased()
                guard !key.isEmpty else { continue }
                let name = exercise.name.trimmingCharacters(in: .whitespaces)
                let candidate = Mark(date: workout.date, weightKg: weight,
                                     reps: exercise.reps, displayName: name)
                if let current = bestInSession[key],
                   weight < current.weightKg ||
                   (weight == current.weightKg && exercise.reps <= current.reps) {
                    continue
                }
                bestInSession[key] = candidate
            }
            for (key, mark) in bestInSession {
                marksByKey[key, default: []].append(mark)
            }
        }

        let rows: [(date: Date, line: String)] = marksByKey.values.compactMap { marks in
            let sorted = marks.sorted { $0.date < $1.date }
            guard sorted.count >= 2 else { return nil }
            let prev = sorted[sorted.count - 2]
            let last = sorted[sorted.count - 1]
            let fmt = { String(format: "%g", $0) }
            let delta: String
            if last.weightKg == prev.weightKg {
                delta = "sin cambio"
            } else {
                let pct = Int(((last.weightKg - prev.weightKg) / prev.weightKg * 100).rounded())
                delta = "\(pct > 0 ? "+" : "")\(pct)%"
            }
            let line = "\(last.displayName): \(fmt(prev.weightKg)) → \(fmt(last.weightKg)) kg/mango (\(delta))"
            return (last.date, line)
        }

        return rows.sorted { $0.date > $1.date }.prefix(limit).map(\.line)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/StrengthProgressionTests -quiet 2>&1 | tail -20`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/StrengthProgression.swift MyFitTests/StrengthProgressionTests.swift MyFit.xcodeproj/project.pbxproj
git commit -m "feat: StrengthProgression — última marca vs anterior por ejercicio"
```

---

### Task 4: Tarjeta "Hoy" con línea de ejercicio y restante neto

**Files:**
- Modify: `MyFit/Views/Meals/MealListView.swift`

**Interfaces:**
- Consumes: `EnergyBalance.forDay(_:meals:workouts:goal:calendar:)` (Task 1).
- Produces: nada consumible por otros tasks (cambio de UI).

Nota: no hay tests de UI en el repo; esta task verifica con build + suite completa, y el E2E visual lo hace el usuario al final.

- [ ] **Step 1: Añadir query de workouts y balance del día**

En `MealListView.swift`, tras la línea 6 (`@Query(sort: \Meal.date...)`), añadir:

```swift
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
```

Y tras el bloque de computed properties (líneas 22-27), añadir:

```swift
    private var todayBalance: EnergyBalance {
        EnergyBalance.forDay(Date(), meals: meals, workouts: workouts, goal: calorieGoal)
    }
```

Sustituir la propiedad `remaining` (línea 27) por:

```swift
    private var remaining: Int { max(0, todayBalance.netRemaining) }
```

- [ ] **Step 2: Línea de ejercicio y color del restante**

En la tarjeta "Hoy", entre el cierre del `HStack` principal (línea 63) y el `GeometryReader` (línea 65), insertar:

```swift
                        if todayBalance.exerciseBurned > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(.orange)
                                Text("Ejercicio: +\(todayBalance.exerciseBurned) kcal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
```

En la línea 61, cambiar la condición del color para que el exceso tenga en cuenta el ejercicio:

```swift
                                    .foregroundStyle(todayKcal > calorieGoal + todayBalance.exerciseBurned ? .red : .green)
```

La barra de progreso (`progress`) NO cambia: sigue siendo `consumed / goal`. La cabecera de días históricos (línea 136) tampoco cambia.

- [ ] **Step 3: Build y suite completa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -20`
Expected: compila y toda la suite verde.

- [ ] **Step 4: Commit**

```bash
git add MyFit/Views/Meals/MealListView.swift
git commit -m "feat: tarjeta Hoy muestra ejercicio y restante neto"
```

---

### Task 5: Asistente — balance neto, proyección, progresión y adherencia

**Files:**
- Modify: `MyFit/Services/NutritionChatService.swift`

**Interfaces:**
- Consumes: `EnergyBalance.forDay` (Task 1), `WeeklyAdherence.lines` (Task 2), `StrengthProgression.lines` (Task 3).
- Produces: nada nuevo consumible (cambio interno del system prompt).

- [ ] **Step 1: Balance neto y proyección en "Comidas registradas hoy"**

Nota de desviación de la spec: la proyección NO se ajusta por la cena planeada porque `PlannedMeal` no guarda kcal — se proyecta con el `netRemaining` tal cual.

En `buildUserDataSection`, antes del bloque `// Comidas registradas hoy` (línea 174), añadir el fetch de entrenos de hoy:

```swift
        // Entrenos de hoy (para el balance neto)
        let todaysWorkouts = (try? context.fetch(FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date >= today },
            sortBy: [SortDescriptor(\.date)]
        ))) ?? []
```

En el mismo bloque de comidas, sustituir (líneas 189-191):

```swift
            if goals.kcal > 0 {
                lines.append("  Restante hoy: \(goals.kcal - kcal) kcal · P\(goals.protein - protein)/C\(goals.carbs - carbs)/G\(goals.fat - fat) g.")
            }
```

por:

```swift
            if goals.kcal > 0 {
                let balance = EnergyBalance.forDay(now, meals: meals, workouts: todaysWorkouts, goal: goals.kcal)
                if balance.exerciseBurned > 0 {
                    lines.append("  Ejercicio hoy: +\(balance.exerciseBurned) kcal quemadas entrenando.")
                }
                lines.append("  Restante hoy (neto, ejercicio incluido): \(balance.netRemaining) kcal · P\(goals.protein - protein)/C\(goals.carbs - carbs)/G\(goals.fat - fat) g.")
                if balance.netRemaining > 0 {
                    lines.append("  Proyección: si el resto del día suma ~\(balance.netRemaining) kcal, termina en objetivo.")
                }
            }
```

- [ ] **Step 2: Secciones de progresión y adherencia**

Tras el bloque `// Últimos entrenos` (cierra en la línea 267), insertar:

```swift
        // Progresión de fuerza (última marca vs sesión anterior por ejercicio)
        let allWorkoutsDescriptor = FetchDescriptor<Workout>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let allWorkouts = try? context.fetch(allWorkoutsDescriptor) {
            let progression = StrengthProgression.lines(from: allWorkouts)
            if !progression.isEmpty {
                lines.append("- Progresión de fuerza (última marca vs sesión anterior):")
                for line in progression {
                    lines.append("  · \(line)")
                }
            }
        }

        // Resumen semanal de adherencia (kcal netas)
        if let weekStart = cal.date(byAdding: .day, value: -6, to: today) {
            let weekMeals = (try? context.fetch(FetchDescriptor<Meal>(
                predicate: #Predicate { $0.date >= weekStart }
            ))) ?? []
            let weekWorkouts = (try? context.fetch(FetchDescriptor<Workout>(
                predicate: #Predicate { $0.date >= weekStart }
            ))) ?? []
            let adherence = WeeklyAdherence.lines(today: now, meals: weekMeals, workouts: weekWorkouts,
                                                  kcalGoal: goals.kcal, proteinGoal: goals.protein)
            if !adherence.isEmpty {
                lines.append("- Resumen semanal:")
                for line in adherence {
                    lines.append("  · \(line)")
                }
            }
        }
```

- [ ] **Step 3: Instrucciones del prompt**

En el bloque "Cómo usar estos datos" (líneas 99-104), añadir una línea tras "Al sugerir comida, menciona las calorías y macros que le quedan hoy":

```swift
            - El restante ya incluye el ejercicio de hoy: no vuelvas a sumar las kcal quemadas al aconsejar
```

En el bloque de rutinas Speediance (líneas 123-131), añadir tras la línea de "Pesos en kg POR MANGO...":

```swift
        - Progresión: si en "Progresión de fuerza" la última marca subió o se mantuvo, propón un +2,5-5% sobre ella; si es la primera vez que aparece el ejercicio, sé conservador
```

- [ ] **Step 4: Build y suite completa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -20`
Expected: compila y toda la suite verde (no hay tests del prompt; el cambio se valida en el E2E).

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/NutritionChatService.swift
git commit -m "feat: asistente ve balance neto, proyección, progresión y adherencia semanal"
```

---

### Task 6: Reporte semanal con kcal netas y días en objetivo

**Files:**
- Modify: `MyFit/Services/ReportBuilder.swift`
- Test: `MyFitTests/ReportBuilderTests.swift` (añadir tests; seguir el patrón `makeContainer()`/`day(_:)` ya existente)

**Interfaces:**
- Consumes: modelo `ReportSnapshot` existente (sin cambios de esquema).
- Produces: `ReportBuilder.formatText(_:avgNetKcal:daysInGoal:)` — mismos dos primeros parámetros, más dos opcionales con default `nil` (los callers y tests existentes siguen compilando).

- [ ] **Step 1: Write the failing test**

Añadir a `MyFitTests/ReportBuilderTests.swift` dentro del struct existente:

```swift
    @Test("el texto incluye kcal netas y días en objetivo cuando hay ejercicio")
    func netKcalInText() throws {
        let context = ModelContext(try makeContainer())
        // 2200 kcal comidas − 300 ejercicio = 1900 netas → en objetivo ±10% de 2000
        context.insert(Meal(date: day(0), name: "x", calories: 2200,
                            proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        context.insert(Workout(date: day(0), caloriesBurned: 300))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context,
                                           goals: ReportBuilder.MacroGoals(kcal: 2000, protein: 0, carbs: 0, fat: 0))
        #expect(snapshot.reportText.contains("Kcal netas (descontando ejercicio): 1900"))
        #expect(snapshot.reportText.contains("1 en objetivo ±10%"))
    }

    @Test("sin ejercicio no hay línea de kcal netas")
    func noNetLineWithoutExercise() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Meal(date: day(0), name: "x", calories: 2000,
                            proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context,
                                           goals: ReportBuilder.MacroGoals(kcal: 2000, protein: 0, carbs: 0, fat: 0))
        #expect(!snapshot.reportText.contains("Kcal netas"))
        #expect(snapshot.reportText.contains("1 en objetivo ±10%"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyFitTests/ReportBuilderTests -quiet 2>&1 | tail -20`
Expected: FAIL ("Kcal netas" no aparece en el texto).

- [ ] **Step 3: Implementación**

En `ReportBuilder.build`, antes de `snapshot.reportText = formatText(snapshot)` (línea 71), añadir:

```swift
        // Kcal netas por día (descontando ejercicio) y días en objetivo ±10%
        let burnedByDay = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.compactMap(\.caloriesBurned).reduce(0, +) }
        let consumedByDay = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.map(\.calories).reduce(0, +) }
        let netDays: [Int] = consumedByDay.map { $0.value - (burnedByDay[$0.key] ?? 0) }
        let avgNetKcal = netDays.isEmpty ? 0.0 : Double(netDays.reduce(0, +)) / Double(netDays.count)
        let daysInGoal: Int? = goals.kcal > 0
            ? netDays.filter { abs(Double($0) - Double(goals.kcal)) <= Double(goals.kcal) * 0.1 }.count
            : nil
```

Y cambiar la asignación del texto:

```swift
        snapshot.reportText = formatText(snapshot, avgNetKcal: avgNetKcal, daysInGoal: daysInGoal)
```

En `formatText`, cambiar la firma y la cabecera de macros:

```swift
    static func formatText(_ snapshot: ReportSnapshot,
                           avgNetKcal: Double? = nil, daysInGoal: Int? = nil) -> String {
```

```swift
        var macroHeader = "🍽️ Macros (media diaria, \(snapshot.daysLogged)/\(snapshot.totalDays) días registrados"
        if let daysInGoal {
            macroHeader += ", \(daysInGoal) en objetivo ±10%"
        }
        macroHeader += "):"
        lines.append(macroHeader)
        lines.append(" · Kcal: \(macroString(snapshot.avgKcal, goal: snapshot.kcalGoal))")
        if let avgNetKcal, snapshot.caloriesBurned > 0 {
            lines.append(" · Kcal netas (descontando ejercicio): \(Int(avgNetKcal.rounded()))")
        }
```

(Sustituye las líneas 108-109 actuales; el resto de `formatText` queda igual.)

- [ ] **Step 4: Run tests — suite completa**

Run: `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -20`
Expected: PASS toda la suite, incluidos los tests existentes de `ReportBuilderTests` y `ReportTextFormattingTests` (firma con defaults: siguen compilando).

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/ReportBuilder.swift MyFitTests/ReportBuilderTests.swift
git commit -m "feat: reporte semanal con kcal netas y días en objetivo"
```

---

## Verificación E2E (con el usuario, tras la Task 6)

1. Día con entreno Speediance importado → la tarjeta Hoy muestra "Ejercicio: +X kcal" y el restante sube.
2. Preguntar al asistente "¿cómo voy hoy?" → menciona lo quemado y la proyección de cena.
3. Pedir rutina de un ejercicio ya entrenado → propone peso progresado (+2,5-5%) sobre la última marca.
4. Generar reporte semanal → incluye línea de kcal netas y días en objetivo.
