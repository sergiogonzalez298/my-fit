import Foundation
import SwiftData
import Testing
@testable import MyFit

@Suite("Recipe · campos Cookidoo")
struct RecipeCookidooTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Workout.self, Exercise.self, WeightEntry.self, Meal.self,
                             Recipe.self, PlannedMeal.self, ChatMessageRecord.self,
                             ReportSnapshot.self])
        return try ModelContainer(for: schema,
                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test("cookidooId e imageURL sobreviven al guardado")
    func cookidooFieldsRoundTrip() throws {
        let container = try makeContainer()
        let writing = ModelContext(container)
        writing.insert(Recipe(name: "Salmón al vapor", source: "cookidoo",
                              cookidooId: "r90756",
                              imageURL: "https://img/r90756.jpg"))
        try writing.save()

        let reading = ModelContext(container)
        let restored = try #require(try reading.fetch(FetchDescriptor<Recipe>()).first)
        #expect(restored.cookidooId == "r90756")
        #expect(restored.imageURL == "https://img/r90756.jpg")
        #expect(restored.source == "cookidoo")
    }

    @Test("las recetas existentes no Cookidoo tienen los campos a nil")
    func defaultsAreNil() throws {
        let container = try makeContainer()
        let writing = ModelContext(container)
        writing.insert(Recipe(name: "Tortilla", source: "ia"))
        try writing.save()

        let reading = ModelContext(container)
        let restored = try #require(try reading.fetch(FetchDescriptor<Recipe>()).first)
        #expect(restored.cookidooId == nil)
        #expect(restored.imageURL == nil)
    }
}
