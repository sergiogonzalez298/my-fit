# Reporte de progreso para el nutricionista, por WhatsApp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el usuario pueda generar, desde una nueva pestaña "Reportes", un resumen de peso/entrenos/macros de un rango de fechas libre y enviarlo por WhatsApp, guardando cada envío como un registro histórico inmutable.

**Architecture:** Un modelo SwiftData nuevo (`ReportSnapshot`) guarda cada reporte generado. Un servicio sin estado (`ReportBuilder`) agrega `WeightEntry`/`Workout`/`Meal` de un rango y redacta el texto. El envío usa el deep link `whatsapp://send` con fallback automático a la hoja de compartir del sistema si WhatsApp no responde. Tres vistas nuevas (`NewReportView`, `ReportsView`, `ReportDetailView`) cubren crear, listar y reenviar/regenerar.

**Tech Stack:** SwiftUI + SwiftData (iOS 17), Swift 6.0, Swift Testing, XcodeGen, Xcode con simulador iPhone 17.

**Spec:** `docs/superpowers/specs/2026-09-11-reporte-semanal-whatsapp-design.md`

## Global Constraints

- Deployment target iOS 17.0. Swift 6.0. `SWIFT_STRICT_CONCURRENCY: minimal` (no tocar).
- Todo el texto visible para el usuario va **en español**. Comentarios de código también en español.
- XcodeGen: **cualquier archivo nuevo exige `xcodegen generate` antes de compilar** (el proyecto usa grupos clásicos, no sincronizados). `MyFit.xcodeproj` se comitea junto al código.
- Objetivos diarios de macros: `UserDefaults.standard`, claves `SyncService.calorieGoalKey` ("dailyCalorieGoal"), `"dailyProteinGoal"`, `"dailyCarbsGoal"`, `"dailyFatGoal"`. Sin valor guardado, `UserDefaults.integer(forKey:)` devuelve `0` — así se detecta "objetivo no configurado".
- Ningún test toca la red ni `UserDefaults.standard` (para no depender de estado global compartido entre tests): los objetivos se inyectan como parámetro en `ReportBuilder.build`.
- Envío: el deep link se intenta con `UIApplication.shared.open(url, options:completionHandler:)`, no con `canOpenURL` (que exige declarar el esquema en Info.plist vía `LSApplicationQueriesSchemes`, algo que este proyecto no tiene y no hace falta añadir). Si el `completionHandler` devuelve `false`, se muestra la hoja de compartir del sistema.
- Fuera de alcance (del spec): envío automático/programado, elegir el contacto dentro de la app, desglose por ejercicio o por comida en el texto, edición manual del texto antes de enviar, exportar a PDF.

**Comandos base** (desde la raíz del repo):

```bash
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20

xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

## File Structure

**Crear:**

| Archivo | Responsabilidad |
|---|---|
| `MyFit/Models/ReportSnapshot.swift` | Registro inmutable de un reporte generado + `update(from:)` para regenerar en sitio |
| `MyFit/Services/ReportBuilder.swift` | Agrega peso/entrenos/macros de un rango y redacta el texto |
| `MyFit/Services/WhatsAppLink.swift` | Construye la URL `whatsapp://send?text=…`, con límite de longitud |
| `MyFit/Views/Reports/WhatsAppSender.swift` | Abre WhatsApp o expone el fallback; `ActivityShareSheet` (hoja de compartir del sistema) |
| `MyFit/Views/Reports/NewReportView.swift` | Sheet: elegir rango, vista previa en vivo, generar y enviar |
| `MyFit/Views/Reports/ReportsView.swift` | Pestaña "Reportes": historial + botón "Nuevo reporte" |
| `MyFit/Views/Reports/ReportDetailView.swift` | Detalle de un reporte guardado: reenviar / editar y regenerar |
| `MyFitTests/ReportSnapshotPersistenceTests.swift` | Persistencia y `update(from:)` |
| `MyFitTests/ReportBuilderTests.swift` | Agregación de peso/entrenos/macros |
| `MyFitTests/ReportTextFormattingTests.swift` | Formato exacto del texto |
| `MyFitTests/WhatsAppLinkTests.swift` | Construcción de la URL y límite de longitud |

**Modificar:** `MyFit/MyFitApp.swift`, `MyFit/Views/ContentView.swift`.

---

### Task 1: Modelo `ReportSnapshot`

**Files:**
- Create: `MyFit/Models/ReportSnapshot.swift`
- Test: `MyFitTests/ReportSnapshotPersistenceTests.swift`
- Modify: `MyFit/MyFitApp.swift`, `MyFit/Views/ContentView.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `@Model final class ReportSnapshot` con las propiedades listadas abajo, inicializador con valores por defecto, y `func update(from other: ReportSnapshot)`. Lo consume `ReportBuilder` (Task 2) y las vistas (Tasks 5-6).

- [ ] **Step 1: Escribir el test que falla**

Crear `MyFitTests/ReportSnapshotPersistenceTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("ReportSnapshot · persistencia")
struct ReportSnapshotPersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self,
                             ReportSnapshot.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    private func makeSnapshot() -> ReportSnapshot {
        ReportSnapshot(rangeStart: Date(timeIntervalSince1970: 1_757_000_000),
                      rangeEnd: Date(timeIntervalSince1970: 1_757_500_000),
                      createdAt: Date(timeIntervalSince1970: 1_757_500_100),
                      reportText: "📋 Reporte de prueba",
                      weightStartKg: 82.4, weightEndKg: 81.9,
                      workoutCount: 4, totalDurationMinutes: 200, caloriesBurned: 1200,
                      avgKcal: 2100, avgProtein: 145, avgCarbs: 210, avgFat: 65,
                      kcalGoal: 2300, proteinGoal: 160, carbsGoal: 220, fatGoal: 70,
                      daysLogged: 6, totalDays: 7)
    }

    @Test("todos los campos sobreviven a guardar y releer")
    func fieldsRoundTrip() throws {
        let container = try makeContainer()
        let writing = ModelContext(container)
        writing.insert(makeSnapshot())
        try writing.save()

        let reading = ModelContext(container)
        let restored = try #require(try reading.fetch(FetchDescriptor<ReportSnapshot>()).first)

        #expect(restored.reportText == "📋 Reporte de prueba")
        #expect(restored.weightStartKg == 82.4)
        #expect(restored.weightEndKg == 81.9)
        #expect(restored.workoutCount == 4)
        #expect(restored.totalDurationMinutes == 200)
        #expect(restored.caloriesBurned == 1200)
        #expect(restored.avgKcal == 2100)
        #expect(restored.kcalGoal == 2300)
        #expect(restored.daysLogged == 6)
        #expect(restored.totalDays == 7)
    }

    @Test("sin pesadas en el rango, los dos campos de peso son nil")
    func weightFieldsCanBeNil() throws {
        let container = try makeContainer()
        let writing = ModelContext(container)
        let snapshot = ReportSnapshot(rangeStart: Date(), rangeEnd: Date(),
                                      createdAt: Date(), reportText: "sin peso")
        writing.insert(snapshot)
        try writing.save()

        let reading = ModelContext(container)
        let restored = try #require(try reading.fetch(FetchDescriptor<ReportSnapshot>()).first)
        #expect(restored.weightStartKg == nil)
        #expect(restored.weightEndKg == nil)
    }

    @Test("update(from:) copia todos los campos del otro snapshot")
    func updateCopiesEveryField() throws {
        let original = ReportSnapshot(rangeStart: Date(timeIntervalSince1970: 0),
                                      rangeEnd: Date(timeIntervalSince1970: 0),
                                      createdAt: Date(timeIntervalSince1970: 0),
                                      reportText: "viejo")
        let updated = makeSnapshot()

        original.update(from: updated)

        #expect(original.reportText == "📋 Reporte de prueba")
        #expect(original.rangeStart == updated.rangeStart)
        #expect(original.rangeEnd == updated.rangeEnd)
        #expect(original.weightStartKg == 82.4)
        #expect(original.workoutCount == 4)
        #expect(original.avgKcal == 2100)
        #expect(original.kcalGoal == 2300)
        #expect(original.daysLogged == 6)
        #expect(original.totalDays == 7)
    }
}
```

- [ ] **Step 2: Ejecutar y comprobar que falla**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: falla al compilar, `ReportSnapshot` no existe.

- [ ] **Step 3: Implementar el modelo**

Crear `MyFit/Models/ReportSnapshot.swift`:

```swift
import Foundation
import SwiftData

/// Registro inmutable de un reporte generado y enviado (o listo para enviar).
/// El texto se guarda literal: es el registro de lo que de verdad se compartió,
/// independiente de que luego cambie el formato o los datos de origen.
@Model
final class ReportSnapshot {
    var rangeStart: Date
    var rangeEnd: Date
    var createdAt: Date
    var reportText: String

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
    var daysLogged: Int
    var totalDays: Int

    init(rangeStart: Date, rangeEnd: Date, createdAt: Date, reportText: String,
         weightStartKg: Double? = nil, weightEndKg: Double? = nil,
         workoutCount: Int = 0, totalDurationMinutes: Int = 0, caloriesBurned: Int = 0,
         avgKcal: Double = 0, avgProtein: Double = 0, avgCarbs: Double = 0, avgFat: Double = 0,
         kcalGoal: Int = 0, proteinGoal: Int = 0, carbsGoal: Int = 0, fatGoal: Int = 0,
         daysLogged: Int = 0, totalDays: Int = 0) {
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.createdAt = createdAt
        self.reportText = reportText
        self.weightStartKg = weightStartKg
        self.weightEndKg = weightEndKg
        self.workoutCount = workoutCount
        self.totalDurationMinutes = totalDurationMinutes
        self.caloriesBurned = caloriesBurned
        self.avgKcal = avgKcal
        self.avgProtein = avgProtein
        self.avgCarbs = avgCarbs
        self.avgFat = avgFat
        self.kcalGoal = kcalGoal
        self.proteinGoal = proteinGoal
        self.carbsGoal = carbsGoal
        self.fatGoal = fatGoal
        self.daysLogged = daysLogged
        self.totalDays = totalDays
    }

    /// Copia los campos agregados de `other` sobre este registro, para "editar y
    /// regenerar" sin crear un segundo registro en el historial.
    func update(from other: ReportSnapshot) {
        rangeStart = other.rangeStart
        rangeEnd = other.rangeEnd
        createdAt = other.createdAt
        reportText = other.reportText
        weightStartKg = other.weightStartKg
        weightEndKg = other.weightEndKg
        workoutCount = other.workoutCount
        totalDurationMinutes = other.totalDurationMinutes
        caloriesBurned = other.caloriesBurned
        avgKcal = other.avgKcal
        avgProtein = other.avgProtein
        avgCarbs = other.avgCarbs
        avgFat = other.avgFat
        kcalGoal = other.kcalGoal
        proteinGoal = other.proteinGoal
        carbsGoal = other.carbsGoal
        fatGoal = other.fatGoal
        daysLogged = other.daysLogged
        totalDays = other.totalDays
    }
}
```

- [ ] **Step 4: Añadir el modelo a los contenedores de la app**

En `MyFit/MyFitApp.swift`, modificar la lista de `.modelContainer(for:)`:

```swift
.modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                      Recipe.self, PlannedMeal.self, ChatMessageRecord.self,
                      ReportSnapshot.self])
```

En `MyFit/Views/ContentView.swift`, modificar el `#Preview` al final del archivo:

```swift
#Preview {
    ContentView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                              Recipe.self, PlannedMeal.self, ReportSnapshot.self],
                        inMemory: true)
}
```

- [ ] **Step 5: Ejecutar y comprobar que pasa**

```bash
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`, 3 tests nuevos en verde.

- [ ] **Step 6: Commit**

```bash
git add MyFit.xcodeproj MyFit/Models/ReportSnapshot.swift MyFit/MyFitApp.swift \
        MyFit/Views/ContentView.swift MyFitTests/ReportSnapshotPersistenceTests.swift
git commit -m "feat: añade el modelo ReportSnapshot"
```

---

### Task 2: `ReportBuilder.build` — agregación de peso, entrenos y macros

**Files:**
- Create: `MyFit/Services/ReportBuilder.swift`
- Test: `MyFitTests/ReportBuilderTests.swift`

**Interfaces:**
- Consumes: `ReportSnapshot` (Task 1), `WeightEntry`, `Workout`, `Meal` (modelos existentes).
- Produces: `enum ReportBuilder` con `struct MacroGoals { var kcal, protein, carbs, fat: Int; static var current: MacroGoals }` y `static func build(from rangeStart: Date, to rangeEnd: Date, context: ModelContext, goals: MacroGoals = .current) -> ReportSnapshot`. `formatText` (Task 3) lo llama al final de `build`, así que este task deja un `formatText` provisional que solo devuelve `""` — Task 3 lo completa y re-testea.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/ReportBuilderTests.swift`:

```swift
import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("ReportBuilder · agregación")
struct ReportBuilderTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self,
                             ReportSnapshot.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Día a `offset` días de hoy, a medianoche — mismo criterio que `WeightEntry.day`.
    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }

    @Test("sin pesadas en el rango, ambos extremos son nil")
    func noWeightEntries() throws {
        let context = ModelContext(try makeContainer())
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.weightStartKg == nil)
        #expect(snapshot.weightEndKg == nil)
    }

    @Test("una sola pesada da el mismo valor en inicio y fin")
    func singleWeightEntry() throws {
        let context = ModelContext(try makeContainer())
        context.insert(WeightEntry(day: day(-2), weightKg: 80.0))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.weightStartKg == 80.0)
        #expect(snapshot.weightEndKg == 80.0)
    }

    @Test("con varias pesadas toma la primera y la última del rango")
    func multipleWeightEntries() throws {
        let context = ModelContext(try makeContainer())
        context.insert(WeightEntry(day: day(-6), weightKg: 82.4))
        context.insert(WeightEntry(day: day(-3), weightKg: 82.0))
        context.insert(WeightEntry(day: day(0), weightKg: 81.9))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.weightStartKg == 82.4)
        #expect(snapshot.weightEndKg == 81.9)
    }

    @Test("las pesadas fuera del rango no cuentan")
    func weightOutsideRangeExcluded() throws {
        let context = ModelContext(try makeContainer())
        context.insert(WeightEntry(day: day(-10), weightKg: 90.0))
        context.insert(WeightEntry(day: day(-3), weightKg: 82.0))
        context.insert(WeightEntry(day: day(5), weightKg: 70.0))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.weightStartKg == 82.0)
        #expect(snapshot.weightEndKg == 82.0)
    }

    @Test("cuenta, minutos y calorías de entrenos solo dentro del rango")
    func workoutAggregation() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Workout(date: day(-5), type: .strength, durationMinutes: 60, caloriesBurned: 400))
        context.insert(Workout(date: day(-2), type: .cardio, durationMinutes: 40, caloriesBurned: 350))
        context.insert(Workout(date: day(-8), type: .strength, durationMinutes: 90, caloriesBurned: 600))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.workoutCount == 2)
        #expect(snapshot.totalDurationMinutes == 100)
        #expect(snapshot.caloriesBurned == 750)
    }

    @Test("un entreno sin calorías registradas suma 0, no falla")
    func workoutWithoutCalories() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Workout(date: day(-1), type: .cardio, durationMinutes: 30, caloriesBurned: nil))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.workoutCount == 1)
        #expect(snapshot.caloriesBurned == 0)
    }

    @Test("la media de macros se calcula solo sobre los días con comidas registradas")
    func macroAverageOverLoggedDaysOnly() throws {
        let context = ModelContext(try makeContainer())
        context.insert(Meal(date: day(-6), name: "Desayuno", calories: 500,
                            proteinGrams: 30, carbsGrams: 50, fatGrams: 15))
        context.insert(Meal(date: day(-6), name: "Comida", calories: 700,
                            proteinGrams: 40, carbsGrams: 70, fatGrams: 20))
        context.insert(Meal(date: day(-3), name: "Cena", calories: 600,
                            proteinGrams: 35, carbsGrams: 60, fatGrams: 18))
        try context.save()

        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.daysLogged == 2)
        #expect(snapshot.totalDays == 7)
        #expect(abs(snapshot.avgKcal - 900) < 0.001)
        #expect(abs(snapshot.avgProtein - 52.5) < 0.001)
    }

    @Test("sin comidas registradas, la media es 0 y no divide por cero")
    func noMealsLogged() throws {
        let context = ModelContext(try makeContainer())
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.daysLogged == 0)
        #expect(snapshot.avgKcal == 0)
        #expect(snapshot.avgProtein == 0)
    }

    @Test("totalDays incluye ambos extremos del rango")
    func totalDaysIncludesBothEnds() throws {
        let context = ModelContext(try makeContainer())
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context)
        #expect(snapshot.totalDays == 7)

        let singleDay = ReportBuilder.build(from: day(0), to: day(0), context: context)
        #expect(singleDay.totalDays == 1)
    }

    @Test("los objetivos pasados se reflejan en el snapshot")
    func appliesProvidedGoals() throws {
        let context = ModelContext(try makeContainer())
        let goals = ReportBuilder.MacroGoals(kcal: 2300, protein: 160, carbs: 220, fat: 70)
        let snapshot = ReportBuilder.build(from: day(-6), to: day(0), context: context, goals: goals)
        #expect(snapshot.kcalGoal == 2300)
        #expect(snapshot.proteinGoal == 160)
        #expect(snapshot.carbsGoal == 220)
        #expect(snapshot.fatGoal == 70)
    }
}
```

- [ ] **Step 2: Ejecutar y comprobar que falla**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: falla al compilar, `ReportBuilder` no existe.

- [ ] **Step 3: Implementar `ReportBuilder.build`**

Crear `MyFit/Services/ReportBuilder.swift`:

```swift
import Foundation
import SwiftData

/// Agrega peso, entrenos y macros de un rango de fechas en un `ReportSnapshot`
/// listo para guardar. No inserta nada en el contexto: eso lo decide quien llama.
enum ReportBuilder {

    struct MacroGoals {
        var kcal: Int
        var protein: Int
        var carbs: Int
        var fat: Int

        /// Objetivos guardados en Ajustes. `0` significa "no configurado".
        static var current: MacroGoals {
            let defaults = UserDefaults.standard
            return MacroGoals(kcal: defaults.integer(forKey: SyncService.calorieGoalKey),
                              protein: defaults.integer(forKey: "dailyProteinGoal"),
                              carbs: defaults.integer(forKey: "dailyCarbsGoal"),
                              fat: defaults.integer(forKey: "dailyFatGoal"))
        }
    }

    static func build(from rangeStart: Date, to rangeEnd: Date,
                      context: ModelContext, goals: MacroGoals = .current) -> ReportSnapshot {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: rangeStart)
        let end = calendar.startOfDay(for: rangeEnd)

        let weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.day >= start && $0.day <= end },
            sortBy: [SortDescriptor(\.day)]
        )
        let weights = (try? context.fetch(weightDescriptor)) ?? []

        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.date >= start && $0.date <= end }
        )
        let workouts = (try? context.fetch(workoutDescriptor)) ?? []

        let mealDescriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.date >= start && $0.date <= end }
        )
        let meals = (try? context.fetch(mealDescriptor)) ?? []

        let daysLogged = Set(meals.map { calendar.startOfDay(for: $0.date) }).count
        let divisor = Double(max(daysLogged, 1))
        let kcalTotal = meals.map { Double($0.calories) }.reduce(0, +)
        let proteinTotal = meals.map(\.proteinGrams).reduce(0, +)
        let carbsTotal = meals.map(\.carbsGrams).reduce(0, +)
        let fatTotal = meals.map(\.fatGrams).reduce(0, +)

        let totalDays = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1

        let snapshot = ReportSnapshot(
            rangeStart: start, rangeEnd: end, createdAt: Date(), reportText: "",
            weightStartKg: weights.first?.weightKg,
            weightEndKg: weights.last?.weightKg,
            workoutCount: workouts.count,
            totalDurationMinutes: workouts.map(\.durationMinutes).reduce(0, +),
            caloriesBurned: workouts.compactMap(\.caloriesBurned).reduce(0, +),
            avgKcal: daysLogged == 0 ? 0 : kcalTotal / divisor,
            avgProtein: daysLogged == 0 ? 0 : proteinTotal / divisor,
            avgCarbs: daysLogged == 0 ? 0 : carbsTotal / divisor,
            avgFat: daysLogged == 0 ? 0 : fatTotal / divisor,
            kcalGoal: goals.kcal, proteinGoal: goals.protein,
            carbsGoal: goals.carbs, fatGoal: goals.fat,
            daysLogged: daysLogged, totalDays: totalDays
        )
        snapshot.reportText = formatText(snapshot)
        return snapshot
    }

    /// Completado en la Task 3. De momento devuelve el texto vacío para que
    /// `build` compile y los tests de agregación (que no miran `reportText`) pasen.
    static func formatText(_ snapshot: ReportSnapshot) -> String {
        ""
    }
}
```

- [ ] **Step 4: Ejecutar y comprobar que pasa**

```bash
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`, 10 tests nuevos en verde.

- [ ] **Step 5: Commit**

```bash
git add MyFit.xcodeproj MyFit/Services/ReportBuilder.swift MyFitTests/ReportBuilderTests.swift
git commit -m "feat: añade ReportBuilder.build para agregar peso, entrenos y macros"
```

---

### Task 3: `ReportBuilder.formatText` — redacción del texto

**Files:**
- Modify: `MyFit/Services/ReportBuilder.swift`
- Test: `MyFitTests/ReportTextFormattingTests.swift`

**Interfaces:**
- Consumes: `ReportSnapshot` (Task 1).
- Produces: `ReportBuilder.formatText(_:) -> String` con el formato final. Lo consumen `NewReportView`/`ReportDetailView` (Tasks 5-6) a través de `build(...).reportText`.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/ReportTextFormattingTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("ReportBuilder · formatText")
struct ReportTextFormattingTests {

    private func rangeLabel(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "es_ES")
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func makeSnapshot(
        rangeStart: Date, rangeEnd: Date,
        weightStartKg: Double? = nil, weightEndKg: Double? = nil,
        workoutCount: Int = 0, totalDurationMinutes: Int = 0, caloriesBurned: Int = 0,
        avgKcal: Double = 0, avgProtein: Double = 0, avgCarbs: Double = 0, avgFat: Double = 0,
        kcalGoal: Int = 0, proteinGoal: Int = 0, carbsGoal: Int = 0, fatGoal: Int = 0,
        daysLogged: Int = 0, totalDays: Int = 7
    ) -> ReportSnapshot {
        ReportSnapshot(rangeStart: rangeStart, rangeEnd: rangeEnd, createdAt: Date(), reportText: "",
                      weightStartKg: weightStartKg, weightEndKg: weightEndKg,
                      workoutCount: workoutCount, totalDurationMinutes: totalDurationMinutes,
                      caloriesBurned: caloriesBurned,
                      avgKcal: avgKcal, avgProtein: avgProtein, avgCarbs: avgCarbs, avgFat: avgFat,
                      kcalGoal: kcalGoal, proteinGoal: proteinGoal, carbsGoal: carbsGoal, fatGoal: fatGoal,
                      daysLogged: daysLogged, totalDays: totalDays)
    }

    @Test("reporte completo con peso, entrenos, macros y objetivo")
    func fullReport() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let end = start.addingTimeInterval(6 * 86400)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: end,
                                    weightStartKg: 82.4, weightEndKg: 81.9,
                                    workoutCount: 4, totalDurationMinutes: 200, caloriesBurned: 1200,
                                    avgKcal: 2100, avgProtein: 145, avgCarbs: 210, avgFat: 65,
                                    kcalGoal: 2300, proteinGoal: 160, carbsGoal: 220, fatGoal: 70,
                                    daysLogged: 6, totalDays: 7)

        let text = ReportBuilder.formatText(snapshot)

        let expected = """
        📋 Reporte (\(rangeLabel(start, end)))

        ⚖️ Peso: 82.4 kg → 81.9 kg (-0.5 kg)

        💪 Entrenos: 4 sesiones · 3h 20min · ~1200 kcal quemadas

        🍽️ Macros (media diaria, 6/7 días registrados):
         · Kcal: 2100/2300
         · Proteína: 145/160 g
         · Carbos: 210/220 g
         · Grasa: 65/70 g
        """
        #expect(text == expected)
    }

    @Test("sin pesadas, sin entrenos y sin comidas registradas")
    func emptyRange() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let end = start.addingTimeInterval(6 * 86400)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: end, totalDays: 7)

        let text = ReportBuilder.formatText(snapshot)

        let expected = """
        📋 Reporte (\(rangeLabel(start, end)))

        ⚖️ Peso: sin registros en el periodo

        💪 Entrenos: sin entrenos en el periodo

        🍽️ Macros (media diaria, 0/7 días registrados):
         · Kcal: 0
         · Proteína: 0 g
         · Carbos: 0 g
         · Grasa: 0 g
        """
        #expect(text == expected)
    }

    @Test("sin objetivo configurado, las macros no muestran '/objetivo'")
    func noGoalConfigured() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: start,
                                    avgKcal: 2100, avgProtein: 145, avgCarbs: 210, avgFat: 65,
                                    daysLogged: 1, totalDays: 1)

        let text = ReportBuilder.formatText(snapshot)

        #expect(text.contains(" · Kcal: 2100\n"))
        #expect(text.contains(" · Proteína: 145 g\n"))
    }

    @Test("una sola sesión de entreno usa el singular y omite las calorías si son 0")
    func singleWorkoutUsesSingular() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: start,
                                    workoutCount: 1, totalDurationMinutes: 45, caloriesBurned: 0)

        let text = ReportBuilder.formatText(snapshot)

        #expect(text.contains("💪 Entrenos: 1 sesión · 45min"))
        #expect(!text.contains("kcal quemadas"))
    }

    @Test("duración de más de una hora se muestra en horas y minutos")
    func durationOverAnHour() {
        let start = Date(timeIntervalSince1970: 1_757_376_000)
        let snapshot = makeSnapshot(rangeStart: start, rangeEnd: start,
                                    workoutCount: 2, totalDurationMinutes: 125, caloriesBurned: 300)

        let text = ReportBuilder.formatText(snapshot)

        #expect(text.contains("2h 5min"))
    }
}
```

- [ ] **Step 2: Ejecutar y comprobar que falla**

```bash
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -40
```

Esperado: fallan los 5 tests nuevos (`formatText` devuelve `""`).

- [ ] **Step 3: Implementar `formatText`**

En `MyFit/Services/ReportBuilder.swift`, sustituir el `formatText` provisional por:

```swift
    static func formatText(_ snapshot: ReportSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "es_ES")

        var lines: [String] = []
        lines.append("📋 Reporte (\(formatter.string(from: snapshot.rangeStart)) - \(formatter.string(from: snapshot.rangeEnd)))")
        lines.append("")

        if let start = snapshot.weightStartKg, let end = snapshot.weightEndKg {
            let delta = end - start
            let sign = delta >= 0 ? "+" : ""
            lines.append("⚖️ Peso: \(weightString(start)) kg → \(weightString(end)) kg (\(sign)\(weightString(delta)) kg)")
        } else {
            lines.append("⚖️ Peso: sin registros en el periodo")
        }
        lines.append("")

        if snapshot.workoutCount > 0 {
            let hours = snapshot.totalDurationMinutes / 60
            let minutes = snapshot.totalDurationMinutes % 60
            let durationText = hours > 0 ? "\(hours)h \(minutes)min" : "\(minutes)min"
            let sessionWord = snapshot.workoutCount == 1 ? "sesión" : "sesiones"
            var workoutLine = "💪 Entrenos: \(snapshot.workoutCount) \(sessionWord) · \(durationText)"
            if snapshot.caloriesBurned > 0 {
                workoutLine += " · ~\(snapshot.caloriesBurned) kcal quemadas"
            }
            lines.append(workoutLine)
        } else {
            lines.append("💪 Entrenos: sin entrenos en el periodo")
        }
        lines.append("")

        lines.append("🍽️ Macros (media diaria, \(snapshot.daysLogged)/\(snapshot.totalDays) días registrados):")
        lines.append(" · Kcal: \(macroString(snapshot.avgKcal, goal: snapshot.kcalGoal))")
        lines.append(" · Proteína: \(macroString(snapshot.avgProtein, goal: snapshot.proteinGoal, unit: "g"))")
        lines.append(" · Carbos: \(macroString(snapshot.avgCarbs, goal: snapshot.carbsGoal, unit: "g"))")
        lines.append(" · Grasa: \(macroString(snapshot.avgFat, goal: snapshot.fatGoal, unit: "g"))")

        return lines.joined(separator: "\n")
    }

    private static func macroString(_ value: Double, goal: Int, unit: String = "") -> String {
        let rounded = Int(value.rounded())
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return goal > 0 ? "\(rounded)/\(goal)\(suffix)" : "\(rounded)\(suffix)"
    }

    private static func weightString(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
```

- [ ] **Step 4: Ejecutar y comprobar que pasa**

```bash
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -40
```

Esperado: `** TEST SUCCEEDED **`, todos los tests en verde (los de la Task 2 incluidos, que no miran `reportText`).

- [ ] **Step 5: Commit**

```bash
git add MyFit/Services/ReportBuilder.swift MyFitTests/ReportTextFormattingTests.swift
git commit -m "feat: redacta el texto del reporte en ReportBuilder.formatText"
```

---

### Task 4: Envío por WhatsApp — `WhatsAppLink` y `WhatsAppSender`

**Files:**
- Create: `MyFit/Services/WhatsAppLink.swift`
- Create: `MyFit/Views/Reports/WhatsAppSender.swift`
- Test: `MyFitTests/WhatsAppLinkTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `enum WhatsAppLink { static let maxLength: Int; static func url(for text: String) -> URL? }`. `@MainActor enum WhatsAppSender { static func send(_ text: String, fallback: @escaping () -> Void) }`. `struct ActivityShareSheet: UIViewControllerRepresentable` (hoja de compartir del sistema, `init(items: [Any])`). Los consumen `NewReportView` y `ReportDetailView` (Tasks 5-6).

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/WhatsAppLinkTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("WhatsAppLink")
struct WhatsAppLinkTests {

    @Test("genera una URL whatsapp://send")
    func buildsURL() {
        let url = WhatsAppLink.url(for: "Hola mundo")
        #expect(url?.scheme == "whatsapp")
        #expect(url?.host == "send")
    }

    @Test("el texto sobrevive codificado en la query, con saltos de línea y emoji")
    func textRoundTrips() {
        let text = "Línea 1\nLínea 2 con emoji 📋 y espacios"
        let url = WhatsAppLink.url(for: text)
        let decoded = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first(where: { $0.name == "text" })?.value
        #expect(decoded == text)
    }

    @Test("un texto vacío no genera URL")
    func emptyTextReturnsNil() {
        #expect(WhatsAppLink.url(for: "") == nil)
    }

    @Test("un texto por encima del límite no genera deep link")
    func tooLongTextReturnsNil() {
        let longText = String(repeating: "a", count: WhatsAppLink.maxLength + 1)
        #expect(WhatsAppLink.url(for: longText) == nil)
    }

    @Test("un texto justo en el límite sí genera deep link")
    func textAtLimitReturnsURL() {
        let text = String(repeating: "a", count: WhatsAppLink.maxLength)
        #expect(WhatsAppLink.url(for: text) != nil)
    }
}
```

- [ ] **Step 2: Ejecutar y comprobar que falla**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: falla al compilar, `WhatsAppLink` no existe.

- [ ] **Step 3: Implementar `WhatsAppLink`**

Crear `MyFit/Services/WhatsAppLink.swift`:

```swift
import Foundation

/// Construye el deep link de WhatsApp para un texto dado.
enum WhatsAppLink {
    /// Límite prudente de caracteres para el deep link: por encima de esto se
    /// prefiere la hoja de compartir del sistema, que no tiene este límite práctico.
    static let maxLength = 4000

    static func url(for text: String) -> URL? {
        guard !text.isEmpty, text.count <= maxLength else { return nil }
        var components = URLComponents()
        components.scheme = "whatsapp"
        components.host = "send"
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        return components.url
    }
}
```

- [ ] **Step 4: Ejecutar y comprobar que pasa**

```bash
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`, 5 tests nuevos en verde.

- [ ] **Step 5: Implementar `WhatsAppSender` y `ActivityShareSheet`**

No son automatizables (dependen de `UIApplication`/`UIActivityViewController`); se verifican manualmente en la Task 6, cuando haya una pantalla real que los dispare.

Crear `MyFit/Views/Reports/WhatsAppSender.swift`:

```swift
import SwiftUI
import UIKit

/// Intenta abrir WhatsApp con el texto. Si falla (no está instalado, o el
/// sistema no puede completar la apertura), llama a `fallback` para que quien
/// invoque muestre la hoja de compartir del sistema como alternativa.
@MainActor
enum WhatsAppSender {
    static func send(_ text: String, fallback: @escaping () -> Void) {
        guard let url = WhatsAppLink.url(for: text) else {
            fallback()
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success { fallback() }
        }
    }
}

/// Hoja de compartir estándar de iOS: fallback cuando WhatsApp no responde,
/// y también sirve para elegir otra app o copiar el texto.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 6: Compilar**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MyFit.xcodeproj MyFit/Services/WhatsAppLink.swift MyFit/Views/Reports/WhatsAppSender.swift \
        MyFitTests/WhatsAppLinkTests.swift
git commit -m "feat: añade el envío por WhatsApp con fallback a la hoja de compartir"
```

---

### Task 5: `NewReportView` — elegir rango, previsualizar y enviar

**Files:**
- Create: `MyFit/Views/Reports/NewReportView.swift`

**Interfaces:**
- Consumes: `ReportBuilder.build` (Task 2/3), `ReportSnapshot.update(from:)` (Task 1), `WhatsAppSender.send` / `ActivityShareSheet` (Task 4).
- Produces: `struct NewReportView: View { init(existingSnapshot: ReportSnapshot? = nil) }`. Sin `existingSnapshot`, crea un reporte nuevo (rango por defecto: últimos 7 días). Con `existingSnapshot`, precarga sus fechas y sobrescribe ese mismo registro al generar ("editar y regenerar", usado por la Task 6). Lo consumen `ReportsView` y `ReportDetailView` (Task 6).

No hay target de UI tests en este proyecto (solo `MyFitTests` para modelos/servicios); esta vista se verifica con Xcode Previews y, en la Task 6, manualmente en el simulador dentro del flujo completo.

- [ ] **Step 1: Implementar la vista**

Crear `MyFit/Views/Reports/NewReportView.swift`:

```swift
import SwiftUI
import SwiftData

struct NewReportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Cuando no es nil, "Generar y enviar" sobrescribe este registro en vez de
    /// crear uno nuevo — lo usa "Editar y regenerar" desde ReportDetailView.
    var existingSnapshot: ReportSnapshot?

    @State private var rangeStart: Date
    @State private var rangeEnd: Date
    @State private var savedSnapshot: ReportSnapshot?
    @State private var showingFallbackShare = false
    @State private var textToShare = ""

    init(existingSnapshot: ReportSnapshot? = nil) {
        self.existingSnapshot = existingSnapshot
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _rangeStart = State(initialValue: existingSnapshot?.rangeStart
            ?? calendar.date(byAdding: .day, value: -6, to: today) ?? today)
        _rangeEnd = State(initialValue: existingSnapshot?.rangeEnd ?? today)
    }

    private var isRangeValid: Bool { rangeEnd >= rangeStart }

    private var preview: ReportSnapshot? {
        guard isRangeValid else { return nil }
        return ReportBuilder.build(from: rangeStart, to: rangeEnd, context: context)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Periodo") {
                    DatePicker("Desde", selection: $rangeStart, displayedComponents: .date)
                    DatePicker("Hasta", selection: $rangeEnd, displayedComponents: .date)
                    if !isRangeValid {
                        Text("\"Hasta\" no puede ser anterior a \"Desde\".")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else if let days = preview?.totalDays, days > 31 {
                        Text("El texto puede quedar muy largo con un rango de \(days) días.")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }

                if let preview {
                    Section("Vista previa") {
                        Text(preview.reportText)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Nuevo reporte")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generar y enviar") { generateAndSend() }
                        .disabled(!isRangeValid)
                }
            }
            .sheet(isPresented: $showingFallbackShare) {
                ActivityShareSheet(items: [textToShare])
            }
        }
    }

    private func generateAndSend() {
        guard let built = preview else { return }
        if let target = savedSnapshot ?? existingSnapshot {
            target.update(from: built)
            savedSnapshot = target
        } else {
            context.insert(built)
            savedSnapshot = built
        }
        textToShare = built.reportText
        WhatsAppSender.send(built.reportText) {
            showingFallbackShare = true
        }
    }
}

#Preview {
    NewReportView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                              Recipe.self, PlannedMeal.self, ReportSnapshot.self],
                        inMemory: true)
}
```

- [ ] **Step 2: Compilar**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verificación manual en el canvas de Previews**

Abrir `NewReportView.swift` en Xcode y activar el canvas de Previews (`⌥⌘P` o el botón "Resume"). Comprobar:
- Las fechas por defecto son "hoy" y "hace 6 días".
- La sección "Vista previa" muestra el texto con "sin registros en el periodo" / "sin entrenos en el periodo" (no hay datos sembrados en el contenedor en memoria).
- Poner "Hasta" antes que "Desde" hace aparecer el aviso rojo y deshabilita "Generar y enviar".

- [ ] **Step 4: Commit**

```bash
git add MyFit.xcodeproj MyFit/Views/Reports/NewReportView.swift
git commit -m "feat: añade NewReportView para generar y enviar un reporte"
```

---

### Task 6: `ReportsView` + `ReportDetailView` + pestaña "Reportes"

**Files:**
- Create: `MyFit/Views/Reports/ReportsView.swift`
- Create: `MyFit/Views/Reports/ReportDetailView.swift`
- Modify: `MyFit/Views/ContentView.swift`

**Interfaces:**
- Consumes: `ReportSnapshot` (Task 1), `NewReportView` (Task 5), `WhatsAppSender.send` / `ActivityShareSheet` (Task 4).
- Produces: `struct ReportsView: View` (pestaña), `struct ReportDetailView: View { let snapshot: ReportSnapshot }`. Cierra el flujo completo de principio a fin.

- [ ] **Step 1: Implementar `ReportDetailView`**

Crear `MyFit/Views/Reports/ReportDetailView.swift`:

```swift
import SwiftUI

struct ReportDetailView: View {
    let snapshot: ReportSnapshot

    @State private var showingRegenerateConfirm = false
    @State private var showingEditSheet = false
    @State private var showingFallbackShare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(snapshot.reportText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Text("Generado el \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Reporte")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        WhatsAppSender.send(snapshot.reportText) {
                            showingFallbackShare = true
                        }
                    } label: {
                        Label("Reenviar", systemImage: "paperplane")
                    }
                    Button {
                        showingRegenerateConfirm = true
                    } label: {
                        Label("Editar y regenerar", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("¿Regenerar este reporte?",
                            isPresented: $showingRegenerateConfirm,
                            titleVisibility: .visible) {
            Button("Editar y regenerar") { showingEditSheet = true }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se recalculará con los datos actuales y sustituirá el texto de este reporte.")
        }
        .sheet(isPresented: $showingEditSheet) {
            NewReportView(existingSnapshot: snapshot)
        }
        .sheet(isPresented: $showingFallbackShare) {
            ActivityShareSheet(items: [snapshot.reportText])
        }
    }
}
```

- [ ] **Step 2: Implementar `ReportsView`**

Crear `MyFit/Views/Reports/ReportsView.swift`:

```swift
import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query(sort: \ReportSnapshot.createdAt, order: .reverse) private var snapshots: [ReportSnapshot]
    @State private var showingNewReport = false

    var body: some View {
        NavigationStack {
            Group {
                if snapshots.isEmpty {
                    ContentUnavailableView("Sin reportes",
                                           systemImage: "square.and.arrow.up.on.square",
                                           description: Text("Pulsa + para generar tu primer reporte."))
                } else {
                    List {
                        ForEach(snapshots) { snapshot in
                            NavigationLink {
                                ReportDetailView(snapshot: snapshot)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rangeLabel(snapshot))
                                        .fontWeight(.semibold)
                                    Text("Generado el \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reportes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNewReport = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewReport) {
                NewReportView()
            }
        }
    }

    private func rangeLabel(_ snapshot: ReportSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "es_ES")
        return "\(formatter.string(from: snapshot.rangeStart)) - \(formatter.string(from: snapshot.rangeEnd))"
    }
}

#Preview {
    ReportsView()
        .modelContainer(for: [Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                              Recipe.self, PlannedMeal.self, ReportSnapshot.self],
                        inMemory: true)
}
```

- [ ] **Step 3: Añadir la pestaña "Reportes" a `ContentView`**

En `MyFit/Views/ContentView.swift`, añadir un caso al `TabView` (después de "Ajustes", como sexta pestaña):

```swift
ReportsView()
    .tabItem { Label("Reportes", systemImage: "square.and.arrow.up.on.square") }
    .tag(5)
```

- [ ] **Step 4: Compilar**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verificación manual end-to-end en el simulador**

```bash
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build run 2>&1 | tail -20
```

(O simplemente abrir `MyFit.xcodeproj` en Xcode y pulsar Run sobre el simulador iPhone 17.)

En la app:
1. Ir a la pestaña "Reportes" (icono nuevo) → debe verse el estado vacío "Sin reportes".
2. Pulsar "+" → se abre "Nuevo reporte" con "Desde"/"Hasta" precargados (últimos 7 días) y una vista previa con "sin registros en el periodo" / "sin entrenos en el periodo" (a menos que ya haya datos de otras pestañas).
3. Pulsar "Generar y enviar": el simulador no tiene WhatsApp instalado, así que debe abrirse automáticamente la hoja de compartir del sistema con el texto del reporte.
4. Cerrar la hoja de compartir y la pantalla de "Nuevo reporte" (botón "Cerrar") → el reporte generado debe aparecer ahora en el historial de "Reportes".
5. Tocar esa fila → se abre `ReportDetailView` con el texto y la fecha de generación.
6. Menú "…" → "Reenviar" → vuelve a abrirse la hoja de compartir con el mismo texto.
7. Menú "…" → "Editar y regenerar" → confirmar en el diálogo → se abre "Nuevo reporte" con las mismas fechas precargadas; generar de nuevo no debe crear una segunda fila en el historial, solo actualizar la existente.
8. Ir a Ajustes, poner un objetivo de kcal/proteína/carbos/grasa, registrar una comida y un peso en sus pestañas, y generar un reporte nuevo: comprobar que el texto refleja esos datos (peso inicio/fin, macros con "valor/objetivo").

- [ ] **Step 6: Commit**

```bash
git add MyFit.xcodeproj MyFit/Views/Reports/ReportsView.swift MyFit/Views/Reports/ReportDetailView.swift \
        MyFit/Views/ContentView.swift
git commit -m "feat: añade la pestaña Reportes con historial, detalle y reenvío"
```

## Self-Review

**1. Cobertura del spec:** Modelo de datos → Task 1. `ReportBuilder`/`formatText` (incluidas todas las reglas de "Casos límite": sin datos, media solo sobre `daysLogged`, sin objetivo, una sola pesada) → Tasks 2-3. Envío por WhatsApp con fallback silencioso → Task 4. `NewReportView` (validación de rango, aviso de rango largo) → Task 5. `ReportsView` + `ReportDetailView` (historial, reenviar, editar y regenerar sin duplicar) → Task 6. No queda ningún punto del spec sin tarea.

**2. Placeholders:** Sin “TBD”/“TODO”. El único `formatText` provisional (Task 2, Step 3) devuelve un valor concreto (`""`) y se sustituye explícitamente en la Task 3, Step 3 — no es un placeholder abierto, es una secuencia TDD intencional entre dos tareas.

**3. Consistencia de tipos:** `ReportBuilder.MacroGoals` (Task 2) se referencia igual en la Task 5 vía `.current` por defecto. `ReportSnapshot.update(from:)` (Task 1) se usa igual en `NewReportView` (Task 5). `WhatsAppSender.send(_:fallback:)` y `ActivityShareSheet(items:)` (Task 4) se llaman con la misma firma en `NewReportView` y `ReportDetailView` (Tasks 5-6). Nombres de propiedades de `ReportSnapshot` iguales en modelo, builder, tests y vistas.
