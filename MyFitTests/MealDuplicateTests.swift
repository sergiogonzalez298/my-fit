import Foundation
import Testing
import UIKit
@testable import MyFit

@Suite("ImageStorage · duplicar")
struct ImageStorageDuplicateTests {

    /// Una imagen mínima real, para no depender de archivos del repo.
    private func makeImage(_ color: UIColor = .red) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    @Test("la copia tiene un nombre distinto y existe en disco")
    func duplicateCreatesNewFile() throws {
        let original = try ImageStorage.save(makeImage())
        defer { ImageStorage.delete(fileName: original) }

        let copy = try ImageStorage.duplicate(fileName: original)
        defer { ImageStorage.delete(fileName: copy) }

        #expect(copy != original)
        #expect(FileManager.default.fileExists(atPath: ImageStorage.url(for: copy).path))
    }

    @Test("la copia conserva los bytes exactos del original")
    func duplicatePreservesBytes() throws {
        let original = try ImageStorage.save(makeImage())
        defer { ImageStorage.delete(fileName: original) }
        let copy = try ImageStorage.duplicate(fileName: original)
        defer { ImageStorage.delete(fileName: copy) }

        // Copiar el archivo, no recodificar la imagen: recodificar perdería calidad
        // en cada duplicado sucesivo.
        let originalBytes = try Data(contentsOf: ImageStorage.url(for: original))
        let copyBytes = try Data(contentsOf: ImageStorage.url(for: copy))
        #expect(originalBytes == copyBytes)
    }

    @Test("borrar el original no deja a la copia sin imagen")
    func deletingOriginalLeavesCopyIntact() throws {
        // Esta es la razón entera de copiar el archivo en vez de compartir el nombre:
        // MealListView borra la foto al borrar la comida.
        let original = try ImageStorage.save(makeImage())
        let copy = try ImageStorage.duplicate(fileName: original)
        defer { ImageStorage.delete(fileName: copy) }

        ImageStorage.delete(fileName: original)

        #expect(FileManager.default.fileExists(atPath: ImageStorage.url(for: original).path) == false)
        #expect(FileManager.default.fileExists(atPath: ImageStorage.url(for: copy).path))
    }

    @Test("duplicar un archivo que no existe lanza")
    func duplicateMissingFileThrows() {
        #expect(throws: (any Error).self) {
            try ImageStorage.duplicate(fileName: "no-existe-\(UUID().uuidString).jpg")
        }
    }
}

@Suite("Meal · duplicar")
struct MealDuplicateTests {

    private let epoch = Date(timeIntervalSince1970: 0)

    private func bread() -> FoodItem {
        FoodItem(name: "Pan integral", grams: 60,
                 kcalPer100g: 247, proteinPer100g: 9, carbsPer100g: 41, fatPer100g: 3)
    }

    @Test("la copia lleva nombre, totales, ingredientes y correcciones")
    func copiesEverything() {
        let original = Meal(date: epoch, name: "Tostada con huevo", calories: 319,
                            proteinGrams: 19.7, carbsGrams: 25.8, fatGrams: 13.9,
                            items: [bread()],
                            corrections: [FoodCorrection(text: "el pan es de centeno")])

        let copy = original.duplicate(on: Date())

        #expect(copy.name == "Tostada con huevo")
        #expect(copy.calories == 319)
        #expect(abs(copy.proteinGrams - 19.7) < 0.0001)
        #expect(abs(copy.carbsGrams - 25.8) < 0.0001)
        #expect(abs(copy.fatGrams - 13.9) < 0.0001)
        #expect(copy.items.count == 1)
        #expect(copy.items[0].name == "Pan integral")
        #expect(copy.items[0].grams == 60)
        #expect(copy.corrections.count == 1)
        #expect(copy.corrections[0].text == "el pan es de centeno")
    }

    @Test("la copia se fecha en el día indicado, no en el del original")
    func usesGivenDateNotTheOriginals() {
        let original = Meal(date: epoch, name: "Tostada", calories: 319,
                            proteinGrams: 19.7, carbsGrams: 25.8, fatGrams: 13.9)
        let today = Date()

        let copy = original.duplicate(on: today)

        #expect(copy.date == today)
        #expect(original.date == epoch)
    }

    @Test("la copia es independiente: editarla no toca el original")
    func copyIsIndependent() {
        let original = Meal(date: epoch, name: "Tostada", calories: 319,
                            proteinGrams: 19.7, carbsGrams: 25.8, fatGrams: 13.9,
                            items: [bread()],
                            corrections: [FoodCorrection(text: "algo")])

        let copy = original.duplicate(on: Date())
        copy.name = "Otra cosa"
        copy.calories = 1
        copy.items = []
        copy.corrections = []

        #expect(original.name == "Tostada")
        #expect(original.calories == 319)
        #expect(original.items.count == 1)
        #expect(original.corrections.count == 1)
    }

    @Test("una comida sin foto se duplica sin foto")
    func noPhotoStaysNil() {
        let original = Meal(date: epoch, name: "Lentejas", calories: 450,
                            proteinGrams: 25, carbsGrams: 60, fatGrams: 12)

        #expect(original.duplicate(on: Date()).photoFileName == nil)
    }

    @Test("una comida con foto se duplica con su propio archivo")
    func photoIsCopiedToItsOwnFile() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let fileName = try ImageStorage.save(image)
        defer { ImageStorage.delete(fileName: fileName) }

        let original = Meal(date: epoch, name: "Tostada", calories: 319,
                            proteinGrams: 19.7, carbsGrams: 25.8, fatGrams: 13.9,
                            photoFileName: fileName)

        let copy = original.duplicate(on: Date())
        let copyName = try #require(copy.photoFileName)
        defer { ImageStorage.delete(fileName: copyName) }

        #expect(copyName != fileName)
        #expect(FileManager.default.fileExists(atPath: ImageStorage.url(for: copyName).path))
    }

    @Test("si el archivo de foto ya no está, la copia queda sin foto en vez de fallar")
    func missingPhotoFileDegradesToNil() {
        // Una comida puede referenciar una foto que ya no existe en disco. Duplicarla
        // tiene que seguir funcionando: mejor un duplicado sin imagen que ningún duplicado.
        let original = Meal(date: epoch, name: "Tostada", calories: 319,
                            proteinGrams: 19.7, carbsGrams: 25.8, fatGrams: 13.9,
                            photoFileName: "no-existe-\(UUID().uuidString).jpg")

        #expect(original.duplicate(on: Date()).photoFileName == nil)
    }
}
