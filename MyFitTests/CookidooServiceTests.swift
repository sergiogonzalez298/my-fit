import Foundation
import Testing
@testable import MyFit

@Suite("CookidooService · parsing del JSON del backend")
struct CookidooServiceTests {

    @Test("decodifica una búsqueda con resultados")
    func decodesSearch() throws {
        let json = """
        {"recipes": [{"id": "r90756", "title": "Salmón al vapor",
                      "imageURL": "https://img/r90756.jpg",
                      "url": "https://cookidoo.es/recipes/recipe/es-ES/r90756"}],
         "total": 128}
        """
        let response = try JSONDecoder().decode(CookidooSearchResponse.self, from: Data(json.utf8))
        #expect(response.total == 128)
        #expect(response.recipes.count == 1)
        #expect(response.recipes[0].id == "r90756")
        #expect(response.recipes[0].title == "Salmón al vapor")
        #expect(response.recipes[0].imageURL?.absoluteString == "https://img/r90756.jpg")
    }

    @Test("decodifica una búsqueda vacía")
    func decodesEmptySearch() throws {
        let json = #"{"recipes": [], "total": 0}"#
        let response = try JSONDecoder().decode(CookidooSearchResponse.self, from: Data(json.utf8))
        #expect(response.recipes.isEmpty)
        #expect(response.total == 0)
    }

    @Test("decodifica detalle con nutrición")
    func decodesDetailWithNutrition() throws {
        let json = """
        {"id": "r90756", "title": "Salmón", "imageURL": null, "url": "u",
         "totalMinutes": 35, "difficulty": "fácil", "servings": 4,
         "ingredientSections": [{"title": null, "items": ["800 g de agua"]}],
         "stepSections": [{"title": null, "items": ["Ponga el agua en el vaso."]}],
         "nutrition": {"calories": 320, "proteinGrams": 28.0, "carbsGrams": 6.0, "fatGrams": 18.0}}
        """
        let detail = try JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
        #expect(detail.totalMinutes == 35)
        #expect(detail.servings == 4)
        #expect(detail.ingredientSections[0].items == ["800 g de agua"])
        #expect(detail.nutrition?.calories == 320)
        #expect(detail.nutrition?.proteinGrams == 28.0)
    }

    @Test("decodifica detalle sin nutrición (nutrition null)")
    func decodesDetailWithoutNutrition() throws {
        let json = """
        {"id": "r1", "title": "X", "imageURL": null, "url": "u",
         "totalMinutes": null, "difficulty": null, "servings": null,
         "ingredientSections": [], "stepSections": [], "nutrition": null}
        """
        let detail = try JSONDecoder().decode(CookidooRecipeDetail.self, from: Data(json.utf8))
        #expect(detail.nutrition == nil)
        #expect(detail.totalMinutes == nil)
    }

    @Test("decodifica la semana del planificador")
    func decodesPlannerWeek() throws {
        let json = """
        {"days": [{"date": "2026-09-22",
                   "recipes": [{"id": "r90756", "title": "Salmón", "totalMinutes": 35}]}]}
        """
        let week = try JSONDecoder().decode(CookidooPlannerWeekResponse.self, from: Data(json.utf8))
        #expect(week.days.count == 1)
        #expect(week.days[0].recipes[0].id == "r90756")
    }
}
