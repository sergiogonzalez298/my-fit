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
