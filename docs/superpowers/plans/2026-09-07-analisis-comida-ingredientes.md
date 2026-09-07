# Análisis de comida por ingredientes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el análisis de una foto de comida devuelva un desglose por ingredientes con pesos editables cuyos macros se recalculan al instante, y que el usuario pueda corregir a la IA en lenguaje natural de forma encadenada.

**Architecture:** El protocolo `AIService` se adelgaza a transporte puro (`complete(prompt:imageData:)`) y toda la lógica de comida pasa a un único `FoodAnalyzer`. Los macros se guardan por 100 g en cada `FoodItem`, de modo que cambiar un peso es aritmética local. Una `MealEditorView` compartida sirve tanto para la captura como para reeditar una comida guardada.

**Tech Stack:** SwiftUI + SwiftData (iOS 17), Swift 6.0, Swift Testing, XcodeGen 2.46, Xcode 26.6.

**Spec:** `docs/superpowers/specs/2026-09-07-analisis-comida-ingredientes-design.md`

## Global Constraints

- Deployment target iOS 17.0. Swift 6.0. `SWIFT_STRICT_CONCURRENCY: minimal` (no subir el nivel en este trabajo).
- Todo el texto visible para el usuario va **en español**. Los comentarios de código también, siguiendo el estilo del repo.
- El proyecto se genera con XcodeGen: **cualquier cambio en `project.yml` exige `xcodegen generate`** antes de compilar. `MyFit.xcodeproj` está en git, así que se comitea junto al `project.yml`.
- `Meal` conserva sus cuatro totales planos (`calories`, `proteinGrams`, `carbsGrams`, `fatGrams`). `MealListView`, `NutritionChatService` y `SyncService` los leen y **no se tocan en este plan**.
- Fuera de alcance, no tocar: `RecipeGeneratorService`, `NutritionChatService`, `Views/Recipes/`, `Views/Plan/`, `Views/Weight/`, `Views/Workouts/`.
- Las propiedades nuevas de `@Model` llevan siempre valor por defecto (requisito de la migración ligera de SwiftData).
- Ningún test toca la red.

**Comandos base** (desde la raíz del repo):

```bash
# Compilar
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20

# Tests
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

## File Structure

**Crear:**

| Archivo | Responsabilidad |
|---|---|
| `MyFit/Models/Macros.swift` | Totales nutricionales: suma y escalado por peso |
| `MyFit/Models/FoodItem.swift` | Un ingrediente: peso, unidad natural, macros/100 g, decodificación validada |
| `MyFit/Models/FoodAnalysis.swift` | Resultado de la IA: nombre + ingredientes + totales de reserva |
| `MyFit/Services/OpenAICompatibleService.swift` | Transporte único para OpenAI, Kimi y NVIDIA |
| `MyFit/Services/FoodAnalyzer.swift` | Prompts, análisis, refinado y búsqueda de macros |
| `MyFit/Views/Meals/MealDraft.swift` | Estado editable compartido por captura y detalle |
| `MyFit/Views/Meals/MealEditorView.swift` | UI de edición: ingredientes, totales vivos, corrección con IA |
| `MyFit/Views/Meals/FoodItemFormView.swift` | Sheet de alta/edición manual de un ingrediente |
| `MyFit/Views/Meals/MealDetailView.swift` | Reedición de una comida guardada |
| `MyFitTests/*` | Tests unitarios |

**Modificar:** `project.yml`, `MyFit/Services/AIService.swift`, `MyFit/Services/ClaudeService.swift`, `MyFit/Services/GeminiService.swift`, `MyFit/Models/Meal.swift`, `MyFit/Views/Meals/MealCaptureView.swift`, `MyFit/Views/Meals/MealListView.swift`.

**Borrar:** `MyFit/Services/OpenAIService.swift`, `MyFit/Services/KimiService.swift`, `MyFit/Services/NvidiaService.swift`.

**Decisión que refina el spec.** El spec preveía un camino aparte para las comidas antiguas sin desglose ("totales editables a mano" más un botón "desglosar en ingredientes con IA"). El plan lo resuelve sin rama especial: al cargar un `Meal` con `items` vacío se sintetiza **un ingrediente único** de 100 g cuyos macros por 100 g son los totales guardados. Así `totals` es siempre la suma de `items`, la UI tiene un solo camino de cálculo, y editar ese ingrediente edita los totales. Misma técnica que para un análisis sin desglose (`fallbackTotals`).

El botón de "desglosar con IA" tampoco hace falta como elemento aparte: el campo de corrección ya está en el editor y ya funciona con foto o sin ella, así que escribir "desglósalo en ingredientes" hace ese trabajo por la misma vía que cualquier otra corrección. Un botón menos que mantener.

---

### Task 1: Target de tests y tipo `Macros`

Sin target de tests no hay ciclo TDD para el resto del plan, así que va primero y entrega ya el primer tipo bajo test.

**Files:**
- Modify: `project.yml`
- Create: `MyFit/Models/Macros.swift`
- Test: `MyFitTests/MacrosTests.swift`

**Interfaces:**
- Consumes: nada.
- Produces: `struct Macros: Codable, Hashable` con `kcal/protein/carbs/fat: Double`, `static let zero`, `static func + (Macros, Macros) -> Macros`, `func scaled(toGrams: Double) -> Macros`. Target `MyFitTests` ejecutable con `xcodebuild test -scheme MyFit`.

- [ ] **Step 1: Añadir el target de tests a `project.yml`**

Añadir al final del bloque `targets:` (mismo nivel de indentación que `MyFit:`) y después un bloque `schemes:` al nivel raíz:

```yaml
  MyFitTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: MyFitTests
    dependencies:
      - target: MyFit
    settings:
      base:
        SWIFT_VERSION: "6.0"
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.sergiogonzalez.myfit.tests

schemes:
  MyFit:
    build:
      targets:
        MyFit: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - MyFitTests
```

El bloque `schemes:` es necesario para que `xcodebuild test -scheme MyFit` encuentre los tests en vez de depender de la autocreación de esquemas de Xcode.

- [ ] **Step 2: Escribir el test que falla**

Crear `MyFitTests/MacrosTests.swift`:

```swift
import Testing
@testable import MyFit

@Suite("Macros")
struct MacrosTests {

    @Test("zero es todo ceros")
    func zeroIsEmpty() {
        #expect(Macros.zero.kcal == 0)
        #expect(Macros.zero.protein == 0)
        #expect(Macros.zero.carbs == 0)
        #expect(Macros.zero.fat == 0)
    }

    @Test("la suma va componente a componente")
    func additionIsComponentwise() {
        let a = Macros(kcal: 100, protein: 10, carbs: 5, fat: 2)
        let b = Macros(kcal: 50, protein: 3, carbs: 1, fat: 4)
        let sum = a + b
        #expect(sum.kcal == 150)
        #expect(sum.protein == 13)
        #expect(sum.carbs == 6)
        #expect(sum.fat == 6)
    }

    @Test("escalar a 100 g deja los valores intactos")
    func scalingTo100gIsIdentity() {
        let per100 = Macros(kcal: 155, protein: 13, carbs: 1.1, fat: 11)
        let scaled = per100.scaled(toGrams: 100)
        #expect(abs(scaled.kcal - 155) < 0.0001)
        #expect(abs(scaled.protein - 13) < 0.0001)
    }

    @Test("escalar reparte proporcionalmente al peso")
    func scalingIsProportional() {
        let per100 = Macros(kcal: 155, protein: 13, carbs: 1.1, fat: 11)
        let scaled = per100.scaled(toGrams: 55)
        #expect(abs(scaled.kcal - 85.25) < 0.0001)
        #expect(abs(scaled.protein - 7.15) < 0.0001)
        #expect(abs(scaled.fat - 6.05) < 0.0001)
    }

    @Test("escalar a 0 g da cero")
    func scalingToZero() {
        let scaled = Macros(kcal: 155, protein: 13, carbs: 1.1, fat: 11).scaled(toGrams: 0)
        #expect(scaled.kcal == 0)
        #expect(scaled.protein == 0)
    }
}
```

- [ ] **Step 3: Regenerar el proyecto y ver el test fallar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: FALLA de compilación con "cannot find 'Macros' in scope". Si en su lugar falla con "scheme not found" o "no test targets", el Step 1 no se aplicó bien: revisar la indentación del YAML antes de seguir.

- [ ] **Step 4: Implementar `Macros`**

Crear `MyFit/Models/Macros.swift`:

```swift
import Foundation

/// Totales nutricionales. Un solo tipo para dejar de arrastrar cuatro campos sueltos.
struct Macros: Codable, Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal,
               protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat)
    }

    /// Escala unos valores expresados POR 100 g al peso indicado.
    func scaled(toGrams grams: Double) -> Macros {
        let factor = grams / 100
        return Macros(kcal: kcal * factor,
                      protein: protein * factor,
                      carbs: carbs * factor,
                      fat: fat * factor)
    }
}
```

- [ ] **Step 5: Ver los tests pasar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **` con 5 tests ejecutados.

- [ ] **Step 6: Commit**

```bash
git add project.yml MyFit.xcodeproj MyFit/Models/Macros.swift MyFitTests/MacrosTests.swift
git commit -m "test: añade target MyFitTests y el tipo Macros"
```

---

### Task 2: `AIService` pasa a ser transporte puro

Se añade `complete(prompt:imageData:)` a los cinco servicios y `analyzeFood` se reimplementa **una sola vez** como extensión del protocolo. Comportamiento de la app idéntico: `MealCaptureView` no se toca.

**Files:**
- Modify: `MyFit/Services/AIService.swift:27-29` (el protocolo)
- Modify: `MyFit/Services/OpenAIService.swift`, `KimiService.swift`, `NvidiaService.swift`, `ClaudeService.swift`, `GeminiService.swift`

**Interfaces:**
- Consumes: `AIServiceError`, `AIServicePrompt.extractJSON(from:)`, `AIServicePrompt.foodAnalysis` (todos ya existen en `AIService.swift`).
- Produces: `protocol AIService { func complete(prompt: String, imageData: Data?) async throws -> String }` y una extensión con `analyzeFood(imageData: Data) async throws -> FoodAnalysis` (temporal, se borra en la Task 6).

- [ ] **Step 1: Cambiar el protocolo**

En `MyFit/Services/AIService.swift`, sustituir el bloque del protocolo por:

```swift
protocol AIService: Sendable {
    /// Envía un prompt (con imagen JPEG opcional) y devuelve el texto crudo de la respuesta.
    func complete(prompt: String, imageData: Data?) async throws -> String
}

extension AIService {
    /// Análisis nutricional de una foto. Temporal: la sustituye `FoodAnalyzer` en la Task 6.
    func analyzeFood(imageData: Data) async throws -> FoodAnalysis {
        let text = try await complete(prompt: AIServicePrompt.foodAnalysis, imageData: imageData)
        return try JSONDecoder().decode(FoodAnalysis.self,
                                        from: AIServicePrompt.extractJSON(from: text))
    }
}
```

- [ ] **Step 2: Convertir `OpenAIService`**

En `MyFit/Services/OpenAIService.swift`, sustituir `analyzeFood` por `complete`. Cambian dos cosas: el `content` se construye desde el prompt recibido y solo añade la imagen si `imageData != nil`, y al final se devuelve el texto crudo en vez de decodificarlo.

```swift
    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let imageData {
            let base64 = imageData.base64EncodedString()
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }
        let payload: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }
```

- [ ] **Step 3: Convertir `KimiService`**

En `MyFit/Services/KimiService.swift`, sustituir `analyzeFood` por:

```swift
    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let imageData {
            let base64 = imageData.base64EncodedString()
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }
```

Sin `response_format` y con timeout de 120 s: son las dos diferencias reales con OpenAI.

- [ ] **Step 4: Convertir `NvidiaService`**

En `MyFit/Services/NvidiaService.swift`, sustituir `analyzeFood` por lo siguiente. `compress(_:)` se queda intacto al final del archivo y ahora solo se aplica si hay imagen:

```swift
    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let imageData {
            let base64 = compress(imageData).base64EncodedString()
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }
        let payload: [String: Any] = [
            "model": visionModel,
            "max_tokens": 1024,
            "temperature": 0.2,
            "stream": false,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return content
    }
```

El campo `model` de este struct no se usa en este método —solo `visionModel`—; ya era así antes del cambio.

- [ ] **Step 5: Convertir `ClaudeService`**

En `MyFit/Services/ClaudeService.swift`, sustituir `analyzeFood` por:

```swift
    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = []
        // Claude rinde mejor con la imagen ANTES del texto; se respeta el orden original.
        if let imageData {
            content.append([
                "type": "image",
                "source": ["type": "base64",
                           "media_type": "image/jpeg",
                           "data": imageData.base64EncodedString()]
            ])
        }
        content.append(["type": "text", "text": prompt])

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct MessagesResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text, !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }
```

- [ ] **Step 6: Convertir `GeminiService`**

En `MyFit/Services/GeminiService.swift`, sustituir `analyzeFood` por:

```swift
    func complete(prompt: String, imageData: Data?) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!

        var parts: [[String: Any]] = [["text": prompt]]
        if let imageData {
            parts.append(["inline_data": ["mime_type": "image/jpeg",
                                          "data": imageData.base64EncodedString()]])
        }
        let payload: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["maxOutputTokens": 1024, "temperature": 0.2]
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.compactMap(\.text).joined(),
              !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }
```

- [ ] **Step 7: Compilar y verificar que nada cambió**

```bash
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`. `MealCaptureView.swift:175` sigue llamando a `service.analyzeFood(imageData:)` sin cambios y compila contra la extensión del protocolo.

- [ ] **Step 8: Commit**

```bash
git add MyFit/Services
git commit -m "refactor: AIService pasa a transporte puro con complete(prompt:imageData:)"
```

---

### Task 3: Colapsar OpenAI, Kimi y NVIDIA en un solo servicio

Los tres hablan `chat/completions`. Tras la Task 2 sus `complete` son casi idénticos; se unifican en uno parametrizado, preservando exactamente las diferencias de cada proveedor.

**Files:**
- Create: `MyFit/Services/OpenAICompatibleService.swift`
- Delete: `MyFit/Services/OpenAIService.swift`, `MyFit/Services/KimiService.swift`, `MyFit/Services/NvidiaService.swift`
- Modify: `MyFit/Services/AIService.swift` (el `switch` de `AIServiceResolver.makeService()`)

**Interfaces:**
- Consumes: `protocol AIService` (Task 2), `UIImage.resized(maxDimension:)` (ya existe en `ImageStorage.swift`).
- Produces: `struct OpenAICompatibleService: AIService` con `init(apiKey:model:endpoint:timeout:requestsJSONObject:maxTokens:temperature:maxImageDimension:imageJPEGQuality:)`.

- [ ] **Step 1: Crear el servicio unificado**

Crear `MyFit/Services/OpenAICompatibleService.swift`:

```swift
import Foundation
import UIKit

/// Transporte para cualquier API con formato `chat/completions` de OpenAI.
/// Cubre OpenAI, Kimi (Moonshot) y NVIDIA NIM; sus diferencias son parámetros, no código.
struct OpenAICompatibleService: AIService {
    let apiKey: String
    let model: String
    let endpoint: URL
    let timeout: TimeInterval
    /// OpenAI acepta `response_format: json_object`; Kimi y NVIDIA no.
    let requestsJSONObject: Bool
    let maxTokens: Int?
    let temperature: Double?
    /// NVIDIA necesita la imagen reducida a 512 px para no pasarse del límite de payload.
    let maxImageDimension: CGFloat?
    let imageJPEGQuality: CGFloat?

    func complete(prompt: String, imageData: Data?) async throws -> String {
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        if let imageData {
            let base64 = preprocess(imageData).base64EncodedString()
            content.append(["type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]])
        }

        var payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [["role": "user", "content": content]]
        ]
        if requestsJSONObject { payload["response_format"] = ["type": "json_object"] }
        if let maxTokens { payload["max_tokens"] = maxTokens }
        if let temperature { payload["temperature"] = temperature }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = timeout

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIServiceError.httpError(status: http.statusCode,
                                           body: String(data: data, encoding: .utf8) ?? "")
        }

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }
        return text
    }

    /// Reduce la imagen solo si el proveedor lo pide. Sin parámetros, se manda tal cual.
    private func preprocess(_ data: Data) -> Data {
        guard let maxImageDimension, let image = UIImage(data: data) else { return data }
        let resized = image.resized(maxDimension: maxImageDimension)
        return resized.jpegData(compressionQuality: imageJPEGQuality ?? 0.7) ?? data
    }
}
```

- [ ] **Step 2: Cablear los tres proveedores en el resolver**

En `MyFit/Services/AIService.swift`, dentro de `AIServiceResolver.makeService()`, sustituir los tres `case` correspondientes:

```swift
        case .openai:
            return OpenAICompatibleService(
                apiKey: key, model: vision,
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                timeout: 60, requestsJSONObject: true,
                maxTokens: nil, temperature: nil,
                maxImageDimension: nil, imageJPEGQuality: nil)
        case .kimi:
            return OpenAICompatibleService(
                apiKey: key, model: vision,
                endpoint: URL(string: "https://api.moonshot.ai/v1/chat/completions")!,
                timeout: 120, requestsJSONObject: false,
                maxTokens: nil, temperature: nil,
                maxImageDimension: nil, imageJPEGQuality: nil)
        case .nvidia:
            return OpenAICompatibleService(
                apiKey: key, model: vision,
                endpoint: URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!,
                timeout: 120, requestsJSONObject: false,
                maxTokens: 1024, temperature: 0.2,
                maxImageDimension: 512, imageJPEGQuality: 0.5)
```

`NvidiaService` recibía además `model: chatModel(for: provider)`, pero ese campo no se usaba en `analyzeFood`: desaparece sin pérdida.

- [ ] **Step 3: Borrar los tres servicios obsoletos**

```bash
git rm MyFit/Services/OpenAIService.swift MyFit/Services/KimiService.swift MyFit/Services/NvidiaService.swift
```

- [ ] **Step 4: Compilar**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`. Hace falta `xcodegen generate` porque han desaparecido archivos del target.

- [ ] **Step 5: Commit**

```bash
git add -A MyFit project.yml MyFit.xcodeproj
git commit -m "refactor: unifica OpenAI, Kimi y NVIDIA en OpenAICompatibleService"
```

---

### Task 4: `FoodItem` y `FoodCorrection`

El corazón aritmético de la función: macros por 100 g escalados al peso, y conversión unidades ↔ gramos. Incluye la decodificación validada, que es la defensa contra los modelos que devuelven basura.

**Files:**
- Create: `MyFit/Models/FoodItem.swift`
- Test: `MyFitTests/FoodItemTests.swift`

**Interfaces:**
- Consumes: `Macros` (Task 1).
- Produces: `struct FoodItem: Codable, Identifiable, Hashable` con `id: UUID`, `name: String`, `grams: Double`, `unitName: String?`, `gramsPerUnit: Double?`, `kcalPer100g/proteinPer100g/carbsPer100g/fatPer100g: Double`, y las propiedades `per100g: Macros`, `macros: Macros`, `hasUsableUnit: Bool`, `units: Double?` (get/set). Además `struct FoodCorrection: Codable, Hashable` con `text: String` y `date: Date`.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/FoodItemTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("FoodItem")
struct FoodItemTests {

    private func egg(grams: Double = 110) -> FoodItem {
        FoodItem(name: "Huevo cocido", grams: grams,
                 unitName: "ud", gramsPerUnit: 55,
                 kcalPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11)
    }

    @Test("los macros escalan con el peso")
    func macrosScaleWithGrams() {
        let macros = egg(grams: 110).macros
        #expect(abs(macros.kcal - 170.5) < 0.0001)
        #expect(abs(macros.protein - 14.3) < 0.0001)
        #expect(abs(macros.fat - 12.1) < 0.0001)
    }

    @Test("per100g devuelve la tabla sin escalar")
    func per100gIsUnscaled() {
        #expect(egg(grams: 500).per100g.kcal == 155)
    }

    @Test("units convierte gramos a unidades naturales")
    func unitsFromGrams() {
        #expect(egg(grams: 110).units == 2)
        #expect(egg(grams: 55).units == 1)
    }

    @Test("escribir units recalcula los gramos")
    func settingUnitsUpdatesGrams() {
        var item = egg(grams: 110)
        item.units = 3
        #expect(item.grams == 165)
        #expect(abs(item.macros.kcal - 255.75) < 0.0001)
    }

    @Test("sin unidad natural, units es nil y escribirlo no hace nada")
    func noUnitMeansNoUnits() {
        var rice = FoodItem(name: "Arroz cocido", grams: 200,
                            kcalPer100g: 130, proteinPer100g: 2.7,
                            carbsPer100g: 28, fatPer100g: 0.3)
        #expect(rice.units == nil)
        #expect(rice.hasUsableUnit == false)
        rice.units = 5
        #expect(rice.grams == 200)
    }

    @Test("gramsPerUnit no positivo invalida la unidad")
    func nonPositiveGramsPerUnitIsUnusable() {
        var item = egg()
        item.gramsPerUnit = 0
        #expect(item.hasUsableUnit == false)
        #expect(item.units == nil)
    }

    @Test("unitName vacío invalida la unidad")
    func emptyUnitNameIsUnusable() {
        var item = egg()
        item.unitName = ""
        #expect(item.hasUsableUnit == false)
    }
}

@Suite("FoodItem · decodificación")
struct FoodItemDecodingTests {

    private func decode(_ json: String) throws -> FoodItem {
        try JSONDecoder().decode(FoodItem.self, from: Data(json.utf8))
    }

    @Test("decodifica el esquema que devuelve la IA")
    func decodesAISchema() throws {
        let item = try decode("""
        {"name":"Huevo cocido","grams":110,"unitName":"ud","gramsPerUnit":55,
         "kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}
        """)
        #expect(item.name == "Huevo cocido")
        #expect(item.grams == 110)
        #expect(item.gramsPerUnit == 55)
    }

    @Test("genera un id nuevo cuando la IA no lo manda")
    func generatesIdWhenMissing() throws {
        let a = try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        let b = try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        #expect(a.id != b.id)
    }

    @Test("conserva el id cuando viene, para no romper el round-trip")
    func keepsProvidedId() throws {
        let id = UUID()
        let item = try decode(#"{"id":"\#(id.uuidString)","name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        #expect(item.id == id)
    }

    @Test("normaliza unidades incoherentes a nil")
    func normalizesBrokenUnits() throws {
        let item = try decode("""
        {"name":"Pan","grams":60,"unitName":"","gramsPerUnit":0,
         "kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}
        """)
        #expect(item.unitName == nil)
        #expect(item.gramsPerUnit == nil)
    }

    @Test("rechaza nombre vacío")
    func rejectsEmptyName() {
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"   ","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        }
    }

    @Test("rechaza pesos no positivos o absurdos")
    func rejectsBadGrams() {
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"Pan","grams":0,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"Pan","grams":-60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"Pan","grams":9000,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        }
    }

    @Test("rechaza macros fuera de los límites físicos")
    func rejectsImpossibleMacros() {
        // Nada supera las 900 kcal por 100 g (grasa pura).
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"Pan","grams":60,"kcalPer100g":5000,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}"#)
        }
        // Ningún macro puede pasar de 100 g por cada 100 g.
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":250,"carbsPer100g":41,"fatPer100g":3}"#)
        }
        #expect(throws: (any Error).self) {
            try decode(#"{"name":"Pan","grams":60,"kcalPer100g":247,"proteinPer100g":-9,"carbsPer100g":41,"fatPer100g":3}"#)
        }
    }
}
```

- [ ] **Step 2: Ver los tests fallar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: FALLA de compilación con "cannot find 'FoodItem' in scope".

- [ ] **Step 3: Implementar `FoodItem` y `FoodCorrection`**

Crear `MyFit/Models/FoodItem.swift`:

```swift
import Foundation

/// Un alimento dentro de una comida.
/// Los GRAMOS son la fuente de verdad; la unidad natural solo es una forma cómoda de editarlos.
struct FoodItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var grams: Double

    /// Unidad natural del alimento: "ud", "cucharada", "rebanada". nil si no aplica.
    var unitName: String?
    /// Lo que pesa UNA unidad natural. Debe ser > 0 para que la unidad sirva.
    var gramsPerUnit: Double?

    // Macros de tabla, POR CADA 100 g. Es lo que permite recalcular en local al mover el peso.
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double

    init(id: UUID = UUID(),
         name: String,
         grams: Double,
         unitName: String? = nil,
         gramsPerUnit: Double? = nil,
         kcalPer100g: Double,
         proteinPer100g: Double,
         carbsPer100g: Double,
         fatPer100g: Double) {
        self.id = id
        self.name = name
        self.grams = grams
        self.unitName = unitName
        self.gramsPerUnit = gramsPerUnit
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
    }

    /// Los valores de tabla, sin escalar.
    var per100g: Macros {
        Macros(kcal: kcalPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g)
    }

    /// Lo que aporta realmente este ingrediente según su peso.
    var macros: Macros { per100g.scaled(toGrams: grams) }

    /// true solo si la unidad natural es utilizable de verdad.
    var hasUsableUnit: Bool {
        guard let unitName, !unitName.trimmingCharacters(in: .whitespaces).isEmpty,
              let gramsPerUnit, gramsPerUnit > 0 else { return false }
        return true
    }

    /// Cantidad en unidades naturales. nil si no hay unidad utilizable;
    /// escribirlo en ese caso no hace nada.
    var units: Double? {
        get {
            guard hasUsableUnit, let gramsPerUnit else { return nil }
            return grams / gramsPerUnit
        }
        set {
            guard hasUsableUnit, let gramsPerUnit, let newValue else { return }
            grams = newValue * gramsPerUnit
        }
    }

    // MARK: - Decodificación validada

    enum CodingKeys: String, CodingKey {
        case id, name, grams, unitName, gramsPerUnit
        case kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g
    }

    /// Un ingrediente que no supera la validación se descarta en `FoodAnalysis`.
    /// Es preferible perder un ingrediente que guardar 9.000 kcal inventadas.
    enum DecodingProblem: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let detail): return "Ingrediente inválido: \(detail)"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // La IA nunca manda id; solo viene en el round-trip de lo ya guardado.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        let rawName = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else { throw DecodingProblem.invalid("nombre vacío") }
        name = rawName

        let rawGrams = try container.decodeIfPresent(Double.self, forKey: .grams) ?? 0
        guard rawGrams.isFinite, rawGrams > 0, rawGrams <= 5000 else {
            throw DecodingProblem.invalid("peso fuera de rango: \(rawGrams)")
        }
        grams = rawGrams

        kcalPer100g = try Self.validMacro(container, .kcalPer100g, max: 900)
        proteinPer100g = try Self.validMacro(container, .proteinPer100g, max: 100)
        carbsPer100g = try Self.validMacro(container, .carbsPer100g, max: 100)
        fatPer100g = try Self.validMacro(container, .fatPer100g, max: 100)

        let rawUnit = (try container.decodeIfPresent(String.self, forKey: .unitName) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawPerUnit = try container.decodeIfPresent(Double.self, forKey: .gramsPerUnit)
        if rawUnit.isEmpty || !(rawPerUnit ?? 0).isFinite || (rawPerUnit ?? 0) <= 0 {
            unitName = nil
            gramsPerUnit = nil
        } else {
            unitName = rawUnit
            gramsPerUnit = rawPerUnit
        }
    }

    /// 900 kcal/100 g es grasa pura y 100 g/100 g es el tope de cualquier macro:
    /// por encima de eso la IA se ha inventado el dato.
    private static func validMacro(_ container: KeyedDecodingContainer<CodingKeys>,
                                   _ key: CodingKeys,
                                   max limit: Double) throws -> Double {
        let value = try container.decodeIfPresent(Double.self, forKey: key) ?? 0
        guard value.isFinite, value >= 0, value <= limit else {
            throw DecodingProblem.invalid("\(key.stringValue) fuera de rango: \(value)")
        }
        return value
    }
}

/// Lo que el usuario le ha dicho a la IA sobre una comida, en orden.
struct FoodCorrection: Codable, Hashable {
    var text: String
    var date: Date

    init(text: String, date: Date = Date()) {
        self.text = text
        self.date = date
    }
}
```

`encode(to:)` no se escribe: Swift lo sintetiza a partir de `CodingKeys` porque solo definimos `init(from:)`.

- [ ] **Step 4: Ver los tests pasar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyFit/Models/FoodItem.swift MyFitTests/FoodItemTests.swift
git commit -m "feat: FoodItem con macros por 100 g, unidades naturales y decodificación validada"
```

---

### Task 5: `FoodAnalysis` con desglose por ingredientes

Sustituye el `FoodAnalysis` plano que hoy vive en `AIService.swift`. Un ingrediente inválido se descarta sin tirar el análisis entero, y si la IA no desglosa se conservan sus totales planos.

**Files:**
- Create: `MyFit/Models/FoodAnalysis.swift`
- Modify: `MyFit/Services/AIService.swift:3-9` (borrar el `struct FoodAnalysis` viejo)
- Modify: `MyFit/Views/Meals/MealCaptureView.swift:174-179`
- Test: `MyFitTests/FoodAnalysisTests.swift`

**Interfaces:**
- Consumes: `Macros` (Task 1), `FoodItem` (Task 4).
- Produces: `struct FoodAnalysis: Codable` con `name: String`, `items: [FoodItem]`, `fallbackTotals: Macros?`, `var totals: Macros`, e `init(name:items:fallbackTotals:)`.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/FoodAnalysisTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("FoodAnalysis")
struct FoodAnalysisTests {

    private func decode(_ json: String) throws -> FoodAnalysis {
        try JSONDecoder().decode(FoodAnalysis.self, from: Data(json.utf8))
    }

    @Test("decodifica un desglose completo")
    func decodesBreakdown() throws {
        let analysis = try decode("""
        {"name":"Tostada con huevo","items":[
          {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"Huevo cocido","grams":110,"unitName":"ud","gramsPerUnit":55,
           "kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
        """)
        #expect(analysis.name == "Tostada con huevo")
        #expect(analysis.items.count == 2)
        #expect(analysis.fallbackTotals == nil)
    }

    @Test("los totales suman los ingredientes")
    func totalsSumItems() throws {
        let analysis = try decode("""
        {"name":"Tostada con huevo","items":[
          {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"Huevo cocido","grams":110,"kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
        """)
        // Pan: 148,2 kcal · Huevo: 170,5 kcal
        #expect(abs(analysis.totals.kcal - 318.7) < 0.0001)
        #expect(abs(analysis.totals.protein - 19.7) < 0.0001)
    }

    @Test("un ingrediente inválido se descarta y el resto sobrevive")
    func dropsInvalidItemsOnly() throws {
        let analysis = try decode("""
        {"name":"Plato","items":[
          {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"","grams":-5,"kcalPer100g":99999,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
          {"name":"Huevo cocido","grams":110,"kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
        """)
        #expect(analysis.items.count == 2)
        #expect(analysis.items.map(\.name) == ["Pan integral", "Huevo cocido"])
    }

    @Test("sin desglose, guarda los totales planos como reserva")
    func keepsFlatTotalsAsFallback() throws {
        let analysis = try decode(#"{"name":"Plato","calories":412,"protein":32,"carbs":34,"fat":16}"#)
        #expect(analysis.items.isEmpty)
        #expect(analysis.fallbackTotals?.kcal == 412)
        #expect(analysis.totals.protein == 32)
    }

    @Test("si hay desglose, los totales planos se ignoran")
    func itemsWinOverFlatTotals() throws {
        let analysis = try decode("""
        {"name":"Plato","calories":9999,"protein":1,"carbs":1,"fat":1,
         "items":[{"name":"Pan integral","grams":100,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3}]}
        """)
        #expect(analysis.fallbackTotals == nil)
        #expect(abs(analysis.totals.kcal - 247) < 0.0001)
    }

    @Test("sin nada, los totales son cero en vez de reventar")
    func emptyIsZero() throws {
        let analysis = try decode(#"{"name":"Plato"}"#)
        #expect(analysis.items.isEmpty)
        #expect(analysis.totals.kcal == 0)
    }

    @Test("el round-trip conserva los ingredientes para mandárselos a la IA")
    func roundTripsItems() throws {
        let original = FoodAnalysis(
            name: "Tostada",
            items: [FoodItem(name: "Pan integral", grams: 60,
                             kcalPer100g: 247, proteinPer100g: 9, carbsPer100g: 41, fatPer100g: 3)],
            fallbackTotals: nil)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(FoodAnalysis.self, from: data)
        #expect(restored.items.count == 1)
        #expect(restored.items[0].id == original.items[0].id)
        #expect(restored.items[0].grams == 60)
    }
}
```

- [ ] **Step 2: Ver los tests fallar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: FALLA de compilación — el `FoodAnalysis` actual no tiene `items` ni `fallbackTotals`.

- [ ] **Step 3: Implementar el nuevo `FoodAnalysis`**

Crear `MyFit/Models/FoodAnalysis.swift`:

```swift
import Foundation

/// Envoltorio que convierte un elemento inválido en nil en vez de tumbar el array entero.
/// Al no lanzar nunca, el contenedor sin clave avanza bien de índice.
private struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?
    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

/// Resultado del análisis de una comida.
struct FoodAnalysis: Codable {
    var name: String
    var items: [FoodItem]
    /// Totales que dio la IA cuando no supo desglosar. Solo se usan si `items` está vacío.
    var fallbackTotals: Macros?

    init(name: String, items: [FoodItem], fallbackTotals: Macros? = nil) {
        self.name = name
        self.items = items
        self.fallbackTotals = fallbackTotals
    }

    var totals: Macros {
        items.isEmpty ? (fallbackTotals ?? .zero) : items.map(\.macros).reduce(.zero, +)
    }

    /// Las cuatro claves planas son el esquema viejo: algunos modelos siguen respondiendo así.
    enum CodingKeys: String, CodingKey {
        case name, items, calories, protein, carbs, fat
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try container.decodeIfPresent(String.self, forKey: .name) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let wrapped = (try? container.decode([Lossy<FoodItem>].self, forKey: .items)) ?? []
        items = wrapped.compactMap(\.value)

        if items.isEmpty, let kcal = Self.number(container, .calories) {
            fallbackTotals = Macros(kcal: kcal,
                                    protein: Self.number(container, .protein) ?? 0,
                                    carbs: Self.number(container, .carbs) ?? 0,
                                    fat: Self.number(container, .fat) ?? 0)
        } else {
            fallbackTotals = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        if let fallbackTotals {
            try container.encode(fallbackTotals.kcal, forKey: .calories)
            try container.encode(fallbackTotals.protein, forKey: .protein)
            try container.encode(fallbackTotals.carbs, forKey: .carbs)
            try container.encode(fallbackTotals.fat, forKey: .fat)
        }
    }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>,
                               _ key: CodingKeys) -> Double? {
        guard let value = try? container.decodeIfPresent(Double.self, forKey: key),
              value.isFinite, value >= 0 else { return nil }
        return value
    }
}
```

- [ ] **Step 4: Borrar el `FoodAnalysis` viejo**

En `MyFit/Services/AIService.swift`, borrar por completo el bloque de las líneas 3-9:

```swift
struct FoodAnalysis: Codable {
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
}
```

- [ ] **Step 5: Adaptar `MealCaptureView` a los totales**

En `MyFit/Views/Meals/MealCaptureView.swift`, dentro de `analyze()`, sustituir las cinco asignaciones que leen los campos planos:

```swift
                let result = try await service.analyzeFood(imageData: data)
                let totals = result.totals
                name = result.name
                calories = Int(totals.kcal.rounded())
                protein = totals.protein
                carbs = totals.carbs
                fat = totals.fat
                phase = .editing
```

Es un apaño de transición: la Task 11 sustituye esta vista por el editor de ingredientes.

- [ ] **Step 6: Ver los tests pasar y compilar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MyFit/Models/FoodAnalysis.swift MyFit/Services/AIService.swift \
        MyFit/Views/Meals/MealCaptureView.swift MyFitTests/FoodAnalysisTests.swift
git commit -m "feat: FoodAnalysis con desglose por ingredientes y totales de reserva"
```

---

### Task 6: `FoodAnalyzer` — prompts, análisis, refinado y búsqueda

Toda la lógica de comida en un solo sitio, encima del transporte. Aquí muere la extensión temporal de la Task 2.

**Files:**
- Create: `MyFit/Services/FoodAnalyzer.swift`
- Modify: `MyFit/Services/AIService.swift` (borrar la extensión `analyzeFood` y `AIServicePrompt.foodAnalysis`; añadir `makeFoodAnalyzer()`)
- Modify: `MyFit/Views/Meals/MealCaptureView.swift:165-183`
- Test: `MyFitTests/FoodAnalyzerTests.swift`

**Interfaces:**
- Consumes: `AIService.complete(prompt:imageData:)` (Task 2), `FoodAnalysis` (Task 5), `FoodItem`/`FoodCorrection` (Task 4), `AIServicePrompt.extractJSON(from:)`.
- Produces: `struct FoodAnalyzer` con `init(service: any AIService)`, `func analyze(imageData: Data?, current: FoodAnalysis?, corrections: [FoodCorrection]) async throws -> FoodAnalysis`, `func lookUp(foodName: String) async throws -> FoodItem`, y los estáticos `analysisPrompt(current:corrections:hasPhoto:) -> String` y `lookUpPrompt(foodName:) -> String`. Además `AIServiceResolver.makeFoodAnalyzer() -> FoodAnalyzer?`.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/FoodAnalyzerTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

/// Servicio de mentira: devuelve siempre el mismo texto y anota lo que recibió.
/// `@unchecked Sendable` porque los tests son de un solo hilo.
private final class StubAIService: AIService, @unchecked Sendable {
    let response: String
    private(set) var lastPrompt: String?
    private(set) var lastImageData: Data?
    private(set) var callCount = 0

    init(response: String) { self.response = response }

    func complete(prompt: String, imageData: Data?) async throws -> String {
        lastPrompt = prompt
        lastImageData = imageData
        callCount += 1
        return response
    }
}

private let breakdownJSON = """
Aquí tienes el análisis:
{"name":"Tostada con huevo","items":[
  {"name":"Pan integral","grams":60,"kcalPer100g":247,"proteinPer100g":9,"carbsPer100g":41,"fatPer100g":3},
  {"name":"Huevo cocido","grams":110,"unitName":"ud","gramsPerUnit":55,
   "kcalPer100g":155,"proteinPer100g":13,"carbsPer100g":1.1,"fatPer100g":11}]}
"""

@Suite("FoodAnalyzer")
struct FoodAnalyzerTests {

    @Test("analiza una foto y devuelve el desglose, ignorando el texto que rodea al JSON")
    func analyzesPhoto() async throws {
        let stub = StubAIService(response: breakdownJSON)
        let analysis = try await FoodAnalyzer(service: stub)
            .analyze(imageData: Data([0xFF, 0xD8]), current: nil, corrections: [])
        #expect(analysis.items.count == 2)
        #expect(analysis.name == "Tostada con huevo")
        #expect(stub.lastImageData == Data([0xFF, 0xD8]))
    }

    @Test("sin foto, no se manda imagen al servicio")
    func analyzesWithoutPhoto() async throws {
        let stub = StubAIService(response: breakdownJSON)
        _ = try await FoodAnalyzer(service: stub)
            .analyze(imageData: nil, current: nil, corrections: [])
        #expect(stub.lastImageData == nil)
    }

    @Test("una respuesta sin JSON propaga el error")
    func propagatesBadResponse() async {
        let stub = StubAIService(response: "Lo siento, no puedo ayudarte con eso.")
        await #expect(throws: (any Error).self) {
            try await FoodAnalyzer(service: stub)
                .analyze(imageData: nil, current: nil, corrections: [])
        }
    }

    @Test("busca los macros de un alimento suelto sin mandar imagen")
    func looksUpFood() async throws {
        let stub = StubAIService(response: """
        {"name":"Queso fresco batido","grams":100,
         "kcalPer100g":63,"proteinPer100g":10,"carbsPer100g":4,"fatPer100g":0.5}
        """)
        let item = try await FoodAnalyzer(service: stub).lookUp(foodName: "queso fresco batido")
        #expect(item.name == "Queso fresco batido")
        #expect(item.kcalPer100g == 63)
        #expect(stub.lastImageData == nil)
        #expect(stub.lastPrompt?.contains("queso fresco batido") == true)
    }
}

@Suite("FoodAnalyzer · prompts")
struct FoodAnalyzerPromptTests {

    @Test("el primer análisis no menciona correcciones")
    func firstAnalysisHasNoCorrections() {
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: true)
        #expect(prompt.contains("CORRECCIONES") == false)
        #expect(prompt.contains("DESGLOSE ACTUAL") == false)
    }

    @Test("el prompt insiste en que los valores son por 100 g sin escalar")
    func promptStatesPer100gRule() {
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: true)
        #expect(prompt.contains("100 g"))
        #expect(prompt.lowercased().contains("no los escales"))
    }

    @Test("al refinar manda el desglose actual, con los pesos que el usuario haya tocado")
    func refinementIncludesCurrentBreakdown() {
        let current = FoodAnalysis(
            name: "Tostada",
            items: [FoodItem(name: "Pan de centeno", grams: 80,
                             kcalPer100g: 259, proteinPer100g: 9, carbsPer100g: 48, fatPer100g: 3)])
        let prompt = FoodAnalyzer.analysisPrompt(current: current, corrections: [], hasPhoto: true)
        #expect(prompt.contains("DESGLOSE ACTUAL"))
        #expect(prompt.contains("Pan de centeno"))
        #expect(prompt.contains("80"))
    }

    @Test("manda TODAS las correcciones en orden, no solo la última")
    func refinementIncludesEveryCorrectionInOrder() {
        let corrections = [
            FoodCorrection(text: "no es queso crema, es queso fresco batido"),
            FoodCorrection(text: "el pan es de centeno"),
            FoodCorrection(text: "añade una cucharada de aceite")
        ]
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: corrections, hasPhoto: true)
        guard let first = prompt.range(of: "queso fresco batido"),
              let second = prompt.range(of: "el pan es de centeno"),
              let third = prompt.range(of: "una cucharada de aceite") else {
            Issue.record("faltan correcciones en el prompt")
            return
        }
        #expect(first.lowerBound < second.lowerBound)
        #expect(second.lowerBound < third.lowerBound)
    }

    @Test("sin foto, avisa a la IA de que solo tiene el texto")
    func promptSaysThereIsNoPhoto() {
        let prompt = FoodAnalyzer.analysisPrompt(current: nil, corrections: [], hasPhoto: false)
        #expect(prompt.contains("No hay foto"))
    }
}
```

- [ ] **Step 2: Ver los tests fallar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: FALLA de compilación con "cannot find 'FoodAnalyzer' in scope".

- [ ] **Step 3: Implementar `FoodAnalyzer`**

Crear `MyFit/Services/FoodAnalyzer.swift`:

```swift
import Foundation

/// Toda la lógica de análisis de comida: prompts, refinado y decodificación.
/// Vive una sola vez encima del transporte, en vez de repetirse por proveedor.
struct FoodAnalyzer {
    let service: any AIService

    /// Primer análisis y refinado son la misma llamada: `current` nil significa que es la primera.
    /// Se manda el desglose que hay AHORA en pantalla —con las ediciones manuales del usuario—
    /// y no lo que la IA contestó la última vez, para que sus cambios no se pisen.
    func analyze(imageData: Data?,
                 current: FoodAnalysis?,
                 corrections: [FoodCorrection]) async throws -> FoodAnalysis {
        let prompt = Self.analysisPrompt(current: current,
                                         corrections: corrections,
                                         hasPhoto: imageData != nil)
        let text = try await service.complete(prompt: prompt, imageData: imageData)
        return try JSONDecoder().decode(FoodAnalysis.self,
                                        from: AIServicePrompt.extractJSON(from: text))
    }

    /// Macros de tabla de un alimento suelto, para rellenar la ficha al añadirlo a mano.
    func lookUp(foodName: String) async throws -> FoodItem {
        let text = try await service.complete(prompt: Self.lookUpPrompt(foodName: foodName),
                                              imageData: nil)
        return try JSONDecoder().decode(FoodItem.self,
                                        from: AIServicePrompt.extractJSON(from: text))
    }

    // MARK: - Prompts

    private static let schema = """
    {"name": "...", "items": [{"name": "...", "grams": 0, "unitName": null, "gramsPerUnit": null, \
    "kcalPer100g": 0, "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 0}]}
    """

    static func analysisPrompt(current: FoodAnalysis?,
                               corrections: [FoodCorrection],
                               hasPhoto: Bool) -> String {
        var prompt = """
        Analiza esta comida y devuelve su desglose por ingredientes.

        Responde ÚNICAMENTE con un objeto JSON válido, sin markdown ni texto adicional, con esta forma exacta:
        \(schema)

        Reglas:
        - name: nombre breve del plato completo, en español.
        - items: un elemento por cada ingrediente identificable. Desglosa siempre que puedas.
        - grams: peso estimado en gramos de ESE ingrediente dentro del plato.
        - kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g: valores de tabla nutricional POR CADA \
        100 g del alimento. NO los escales a la porción: el peso va aparte, en "grams". Un huevo cocido \
        son 155 kcal por 100 g tanto si en el plato hay 55 g como si hay 110 g.
        - unitName y gramsPerUnit: rellénalos solo si el alimento tiene una unidad natural ("ud" para \
        huevos o piezas, "rebanada", "cucharada", "loncha"). gramsPerUnit es lo que pesa UNA de esas \
        unidades. Si no aplica, pon null en ambos.
        - Nombres de ingredientes en español y concretos: "queso fresco batido", no "queso".
        """

        if !hasPhoto {
            prompt += "\n\nNo hay foto disponible: básate solo en la descripción y las correcciones."
        }

        if let current, !current.items.isEmpty,
           let data = try? JSONEncoder().encode(current),
           let json = String(data: data, encoding: .utf8) {
            prompt += """


            DESGLOSE ACTUAL (el usuario puede haberlo editado a mano; respeta sus pesos salvo que sus \
            correcciones digan lo contrario):
            \(json)
            """
        }

        if !corrections.isEmpty {
            let list = corrections.enumerated()
                .map { "\($0.offset + 1). \"\($0.element.text)\"" }
                .joined(separator: "\n")
            prompt += """


            CORRECCIONES DEL USUARIO, en orden:
            \(list)

            Aplica TODAS las correcciones, no solo la última, y devuelve el desglose completo corregido.
            """
        }

        return prompt
    }

    static func lookUpPrompt(foodName: String) -> String {
        """
        Dame los valores nutricionales de tabla de este alimento: "\(foodName)".

        Responde ÚNICAMENTE con un objeto JSON válido, sin markdown ni texto adicional:
        {"name": "...", "grams": 100, "unitName": null, "gramsPerUnit": null, "kcalPer100g": 0, \
        "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 0}

        Reglas:
        - Los valores son POR CADA 100 g del alimento. NO los escales a una ración.
        - grams: una ración habitual de este alimento, en gramos.
        - unitName y gramsPerUnit: solo si tiene unidad natural; si no, null en ambos.
        - name: el nombre del alimento en español, corregido si hacía falta.
        """
    }
}
```

- [ ] **Step 4: Limpiar `AIService.swift` y añadir la fábrica**

Borrar la extensión `analyzeFood` completa (añadida en la Task 2) y la constante `AIServicePrompt.foodAnalysis`, que ya no usa nadie. `AIServicePrompt.extractJSON` **se queda**: la usan `FoodAnalyzer`, `RecipeGeneratorService` y `NutritionChatService`.

Añadir al final de `AIServiceResolver`:

```swift
    /// Analizador de comida listo para usar, o nil si no hay API key del proveedor de imágenes.
    static func makeFoodAnalyzer() -> FoodAnalyzer? {
        guard let service = makeService() else { return nil }
        return FoodAnalyzer(service: service)
    }
```

- [ ] **Step 5: Pasar `MealCaptureView` por el analizador**

En `MyFit/Views/Meals/MealCaptureView.swift`, en `analyze()`, sustituir la resolución del servicio y la llamada:

```swift
        guard let image,
              let analyzer = AIServiceResolver.makeFoodAnalyzer(),
              let data = ImageStorage.preparedForUpload(image) else {
            phase = .failed("No hay una API key configurada o la imagen no es válida.")
            return
        }
        phase = .analyzing
        Task {
            do {
                let result = try await analyzer.analyze(imageData: data, current: nil, corrections: [])
                let totals = result.totals
                name = result.name
                calories = Int(totals.kcal.rounded())
                protein = totals.protein
                carbs = totals.carbs
                fat = totals.fat
                phase = .editing
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
```

- [ ] **Step 6: Ver los tests pasar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add MyFit/Services MyFit/Views/Meals/MealCaptureView.swift MyFitTests/FoodAnalyzerTests.swift
git commit -m "feat: FoodAnalyzer con refinado conversacional y búsqueda de macros"
```

---

### Task 7: Persistir el desglose en `Meal`

Cambio aditivo con valores por defecto, que es lo que permite la migración ligera de SwiftData. Los cuatro totales planos se quedan: los leen `MealListView`, `NutritionChatService` y `SyncService`, que no se tocan.

**Files:**
- Modify: `MyFit/Models/Meal.swift`

**Interfaces:**
- Consumes: `FoodItem`, `FoodCorrection` (Task 4).
- Produces: `Meal.items: [FoodItem]` y `Meal.corrections: [FoodCorrection]`, ambas con valor por defecto `[]` y parámetros opcionales en el `init`.

- [ ] **Step 1: Añadir las propiedades**

En `MyFit/Models/Meal.swift`, añadir tras `photoFileName` y ampliar el `init`:

```swift
    /// Desglose por ingredientes. Vacío en las comidas guardadas antes de esta función.
    var items: [FoodItem] = []
    /// Lo que el usuario le ha ido diciendo a la IA sobre esta comida.
    var corrections: [FoodCorrection] = []
```

```swift
    init(date: Date = Date(),
         name: String,
         calories: Int,
         proteinGrams: Double,
         carbsGrams: Double,
         fatGrams: Double,
         photoFileName: String? = nil,
         items: [FoodItem] = [],
         corrections: [FoodCorrection] = []) {
        self.date = date
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.photoFileName = photoFileName
        self.items = items
        self.corrections = corrections
    }
```

`corrections` es `[FoodCorrection]` y no `[String]` a propósito: `Recipe.swift` documenta que `Array<String>` da problemas de bridging con CoreData y lo esquiva con `mealSlotsRaw`. Los arrays de structs `Codable` sí funcionan — `Recipe.ingredientSections: [RecipeSection]` es el precedente.

- [ ] **Step 2: Compilar**

```bash
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`. No hace falta tocar `MyFitApp.swift`: `Meal.self` ya está en el `modelContainer`.

- [ ] **Step 3: Verificar la migración con datos previos**

Este paso es manual y **no se puede saltar**: es el único que prueba que las comidas ya guardadas sobreviven.

1. Con el commit anterior (`git stash` de este cambio), lanzar la app en el simulador iPhone 17 y guardar una comida con foto.
2. Restaurar el cambio (`git stash pop`), recompilar y **relanzar sin borrar la app** del simulador.
3. Comprobar que la comida guardada sigue en la lista con sus kcal y macros intactos.

Si la app peta al arrancar con un error de SwiftData, la migración ligera no ha bastado y hace falta un `VersionedSchema`: parar y reportarlo antes de seguir.

- [ ] **Step 4: Commit**

```bash
git add MyFit/Models/Meal.swift
git commit -m "feat: Meal guarda el desglose por ingredientes y el historial de correcciones"
```

---

### Task 8: `MealDraft` — el estado editable compartido

Concentra toda la lógica que la UI necesitaría inventarse: sumar totales, absorber un análisis, sintetizar el ingrediente único de las comidas sin desglose, mover pesos y formatear cantidades. Al vivir aquí y no en la vista, queda bajo test.

**Files:**
- Create: `MyFit/Views/Meals/MealDraft.swift`
- Test: `MyFitTests/MealDraftTests.swift`

**Interfaces:**
- Consumes: `Macros`, `FoodItem`, `FoodCorrection`, `FoodAnalysis`, `Meal`.
- Produces: `@Observable final class MealDraft` con `name: String`, `items: [FoodItem]`, `corrections: [FoodCorrection]`, `photo: UIImage?`; `init(name:items:corrections:photo:)`, `init(meal:photo:)`; `var totals: Macros`; `var analysis: FoodAnalysis`; `func apply(_ analysis: FoodAnalysis)`; `func save(into meal: Meal)`; `func adjustQuantity(at index: Int, by direction: Double)`; `func quantityLabel(for item: FoodItem) -> String`.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `MyFitTests/MealDraftTests.swift`:

```swift
import Foundation
import Testing
@testable import MyFit

@Suite("MealDraft")
struct MealDraftTests {

    private func bread() -> FoodItem {
        FoodItem(name: "Pan integral", grams: 60,
                 kcalPer100g: 247, proteinPer100g: 9, carbsPer100g: 41, fatPer100g: 3)
    }

    private func egg() -> FoodItem {
        FoodItem(name: "Huevo cocido", grams: 110, unitName: "ud", gramsPerUnit: 55,
                 kcalPer100g: 155, proteinPer100g: 13, carbsPer100g: 1.1, fatPer100g: 11)
    }

    @Test("los totales suman los ingredientes")
    func totalsSumItems() {
        let draft = MealDraft(name: "Tostada", items: [bread(), egg()])
        #expect(abs(draft.totals.kcal - 318.7) < 0.0001)
    }

    @Test("sin ingredientes, los totales son cero")
    func emptyTotals() {
        #expect(MealDraft().totals.kcal == 0)
    }

    @Test("aplicar un análisis con desglose sustituye los ingredientes")
    func applyBreakdown() {
        let draft = MealDraft(name: "Algo", items: [bread()])
        draft.apply(FoodAnalysis(name: "Tostada con huevo", items: [bread(), egg()]))
        #expect(draft.name == "Tostada con huevo")
        #expect(draft.items.count == 2)
    }

    @Test("un análisis sin desglose se convierte en un ingrediente único")
    func applyFallbackSynthesizesSingleItem() {
        let draft = MealDraft()
        draft.apply(FoodAnalysis(name: "Plato combinado", items: [],
                                 fallbackTotals: Macros(kcal: 412, protein: 32, carbs: 34, fat: 16)))
        #expect(draft.items.count == 1)
        #expect(draft.items[0].name == "Plato combinado")
        #expect(draft.items[0].grams == 100)
        // El total sigue siendo la suma de items: un solo camino de cálculo.
        #expect(abs(draft.totals.kcal - 412) < 0.0001)
    }

    @Test("una comida guardada sin desglose se abre como ingrediente único")
    func legacyMealBecomesSingleItem() {
        let meal = Meal(name: "Lentejas", calories: 450,
                        proteinGrams: 25, carbsGrams: 60, fatGrams: 12)
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.items.count == 1)
        #expect(draft.items[0].name == "Lentejas")
        #expect(abs(draft.totals.kcal - 450) < 0.0001)
        #expect(abs(draft.totals.protein - 25) < 0.0001)
    }

    @Test("una comida guardada con desglose se abre tal cual")
    func mealWithItemsLoadsThem() {
        let meal = Meal(name: "Tostada", calories: 318, proteinGrams: 19.7,
                        carbsGrams: 25.8, fatGrams: 13.9,
                        items: [bread(), egg()],
                        corrections: [FoodCorrection(text: "el pan es de centeno")])
        let draft = MealDraft(meal: meal, photo: nil)
        #expect(draft.items.count == 2)
        #expect(draft.corrections.count == 1)
    }

    @Test("guardar recalcula los totales planos desde los ingredientes")
    func saveRecomputesFlatTotals() {
        let meal = Meal(name: "viejo", calories: 1, proteinGrams: 1, carbsGrams: 1, fatGrams: 1)
        let draft = MealDraft(name: "  Tostada con huevo  ", items: [bread(), egg()])
        draft.save(into: meal)
        #expect(meal.name == "Tostada con huevo")
        #expect(meal.calories == 319)          // 318,7 redondeado
        #expect(abs(meal.proteinGrams - 19.7) < 0.0001)
        #expect(meal.items.count == 2)
    }

    @Test("analysis expone el desglose actual para mandárselo a la IA")
    func analysisReflectsCurrentItems() {
        let draft = MealDraft(name: "Tostada", items: [bread()])
        draft.items[0].grams = 80
        #expect(draft.analysis.items[0].grams == 80)
        #expect(draft.analysis.name == "Tostada")
    }

    @Test("subir y bajar mueve medias unidades cuando hay unidad natural")
    func adjustStepsByHalfUnits() {
        let draft = MealDraft(items: [egg()])
        draft.adjustQuantity(at: 0, by: 1)
        #expect(draft.items[0].units == 2.5)
        #expect(draft.items[0].grams == 137.5)
        draft.adjustQuantity(at: 0, by: -1)
        #expect(draft.items[0].units == 2)
    }

    @Test("sin unidad natural, se mueve de 5 en 5 gramos")
    func adjustStepsByGrams() {
        let draft = MealDraft(items: [bread()])
        draft.adjustQuantity(at: 0, by: 1)
        #expect(draft.items[0].grams == 65)
    }

    @Test("no se puede bajar hasta cero ni por debajo")
    func adjustClamps() {
        let draft = MealDraft(items: [egg()])
        for _ in 0..<10 { draft.adjustQuantity(at: 0, by: -1) }
        #expect(draft.items[0].units == 0.5)

        let gramsDraft = MealDraft(items: [bread()])
        for _ in 0..<50 { gramsDraft.adjustQuantity(at: 0, by: -1) }
        #expect(gramsDraft.items[0].grams == 1)
    }

    @Test("un índice fuera de rango no hace nada")
    func adjustIgnoresBadIndex() {
        let draft = MealDraft(items: [bread()])
        draft.adjustQuantity(at: 7, by: 1)
        #expect(draft.items[0].grams == 60)
    }

    @Test("la cantidad se muestra en unidades naturales cuando las hay")
    func quantityLabelUsesUnits() {
        let draft = MealDraft()
        #expect(draft.quantityLabel(for: egg()) == "2 ud")
        #expect(draft.quantityLabel(for: bread()) == "60 g")
    }

    @Test("las medias unidades se muestran con coma decimal")
    func quantityLabelFormatsHalves() {
        let draft = MealDraft()
        var oil = FoodItem(name: "Aceite de oliva", grams: 5,
                           unitName: "cucharada", gramsPerUnit: 10,
                           kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100)
        #expect(draft.quantityLabel(for: oil) == "0,5 cucharada")
        oil.grams = 10
        #expect(draft.quantityLabel(for: oil) == "1 cucharada")
    }
}
```

- [ ] **Step 2: Ver los tests fallar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: FALLA de compilación con "cannot find 'MealDraft' in scope".

- [ ] **Step 3: Implementar `MealDraft`**

Crear `MyFit/Views/Meals/MealDraft.swift`:

```swift
import Foundation
import UIKit

/// Estado editable de una comida, compartido por la captura y la reedición.
///
/// Invariante: `items` nunca está vacío tras cargar una comida o aplicar un análisis.
/// Cuando no hay desglose real se sintetiza un ingrediente único de 100 g cuyos macros
/// por 100 g son los totales. Así `totals` es SIEMPRE la suma de `items` y la UI no
/// necesita un segundo camino de cálculo.
@Observable
final class MealDraft {
    var name: String
    var items: [FoodItem]
    var corrections: [FoodCorrection]
    var photo: UIImage?

    init(name: String = "",
         items: [FoodItem] = [],
         corrections: [FoodCorrection] = [],
         photo: UIImage? = nil) {
        self.name = name
        self.items = items
        self.corrections = corrections
        self.photo = photo
    }

    /// Abre una comida guardada. Las anteriores a esta función no tienen desglose:
    /// se representan como un ingrediente único con los totales que ya tenían.
    convenience init(meal: Meal, photo: UIImage?) {
        let items = meal.items.isEmpty
            ? [FoodItem(name: meal.name,
                        grams: 100,
                        kcalPer100g: Double(meal.calories),
                        proteinPer100g: meal.proteinGrams,
                        carbsPer100g: meal.carbsGrams,
                        fatPer100g: meal.fatGrams)]
            : meal.items
        self.init(name: meal.name,
                  items: items,
                  corrections: meal.corrections,
                  photo: photo)
    }

    var totals: Macros { items.map(\.macros).reduce(.zero, +) }

    /// El desglose actual tal y como debe viajar a la IA al refinar.
    var analysis: FoodAnalysis { FoodAnalysis(name: name, items: items) }

    /// Vuelca un resultado de la IA sobre el borrador.
    func apply(_ analysis: FoodAnalysis) {
        if !analysis.name.isEmpty { name = analysis.name }
        if analysis.items.isEmpty, let fallback = analysis.fallbackTotals {
            items = [FoodItem(name: name.isEmpty ? "Plato completo" : name,
                              grams: 100,
                              kcalPer100g: fallback.kcal,
                              proteinPer100g: fallback.protein,
                              carbsPer100g: fallback.carbs,
                              fatPer100g: fallback.fat)]
        } else {
            items = analysis.items
        }
    }

    /// Persiste sobre un `Meal`, recalculando los totales planos desde el desglose.
    func save(into meal: Meal) {
        meal.name = name.trimmingCharacters(in: .whitespaces)
        meal.items = items
        meal.corrections = corrections
        let totals = self.totals
        meal.calories = Int(totals.kcal.rounded())
        meal.proteinGrams = totals.protein
        meal.carbsGrams = totals.carbs
        meal.fatGrams = totals.fat
    }

    /// Mueve la cantidad de un ingrediente: media unidad natural si la tiene, 5 g si no.
    func adjustQuantity(at index: Int, by direction: Double) {
        guard items.indices.contains(index) else { return }
        var item = items[index]
        if item.hasUsableUnit, let current = item.units {
            item.units = max(0.5, current + 0.5 * direction)
        } else {
            item.grams = max(1, item.grams + 5 * direction)
        }
        items[index] = item
    }

    /// Cómo se muestra la cantidad en la fila: "2 ud", "0,5 cucharada" o "60 g".
    func quantityLabel(for item: FoodItem) -> String {
        if item.hasUsableUnit, let units = item.units, let unitName = item.unitName {
            return "\(Self.formatted(units)) \(unitName)"
        }
        return "\(Int(item.grams.rounded())) g"
    }

    /// Un decimal como mucho, coma decimal, y sin ",0" colgando.
    private static func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}
```

- [ ] **Step 4: Ver los tests pasar**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

Esperado: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add MyFit/Views/Meals/MealDraft.swift MyFitTests/MealDraftTests.swift
git commit -m "feat: MealDraft como estado editable compartido de una comida"
```

---

### Task 9: `FoodItemFormView` — alta y edición manual de un ingrediente

El sheet donde se añade a mano un alimento, con el atajo que evita teclear los cuatro macros.

**Files:**
- Create: `MyFit/Views/Meals/FoodItemFormView.swift`

**Interfaces:**
- Consumes: `FoodItem` (Task 4), `FoodAnalyzer.lookUp(foodName:)` (Task 6).
- Produces: `struct FoodItemFormView: View` con `init(item: FoodItem?, analyzer: FoodAnalyzer?, onSave: @escaping (FoodItem) -> Void)`. `item: nil` significa alta.

- [ ] **Step 1: Crear la vista**

Crear `MyFit/Views/Meals/FoodItemFormView.swift`:

```swift
import SwiftUI

/// Alta o edición manual de un ingrediente. `item` nil = alta.
struct FoodItemFormView: View {
    @Environment(\.dismiss) private var dismiss

    /// nil si no hay proveedor de IA configurado: se oculta el atajo de búsqueda.
    let analyzer: FoodAnalyzer?
    let onSave: (FoodItem) -> Void

    private let existingID: UUID?
    private let isNew: Bool

    @State private var name: String
    @State private var grams: Double
    @State private var unitName: String
    @State private var gramsPerUnit: Double
    @State private var kcal: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double

    @State private var isLookingUp = false
    @State private var lookUpError: String?

    init(item: FoodItem?, analyzer: FoodAnalyzer?, onSave: @escaping (FoodItem) -> Void) {
        self.analyzer = analyzer
        self.onSave = onSave
        self.existingID = item?.id
        self.isNew = item == nil
        _name = State(initialValue: item?.name ?? "")
        _grams = State(initialValue: item?.grams ?? 100)
        _unitName = State(initialValue: item?.unitName ?? "")
        _gramsPerUnit = State(initialValue: item?.gramsPerUnit ?? 0)
        _kcal = State(initialValue: item?.kcalPer100g ?? 0)
        _protein = State(initialValue: item?.proteinPer100g ?? 0)
        _carbs = State(initialValue: item?.carbsPer100g ?? 0)
        _fat = State(initialValue: item?.fatPer100g ?? 0)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alimento") {
                    TextField("Nombre", text: $name)
                    numberRow("Peso", value: $grams, suffix: "g")
                }

                if analyzer != nil {
                    Section {
                        Button {
                            lookUp()
                        } label: {
                            HStack {
                                Label("Buscar macros con IA", systemImage: "sparkles")
                                Spacer()
                                if isLookingUp { ProgressView() }
                            }
                        }
                        .disabled(trimmedName.isEmpty || isLookingUp)
                        if let lookUpError {
                            Text(lookUpError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text("Rellena los valores por 100 g a partir del nombre. Puedes corregirlos después.")
                    }
                }

                Section("Por cada 100 g") {
                    numberRow("Calorías", value: $kcal, suffix: "kcal")
                    numberRow("Proteína", value: $protein, suffix: "g")
                    numberRow("Carbohidratos", value: $carbs, suffix: "g")
                    numberRow("Grasa", value: $fat, suffix: "g")
                }

                Section {
                    TextField("Unidad (ud, cucharada, rebanada…)", text: $unitName)
                    numberRow("Peso por unidad", value: $gramsPerUnit, suffix: "g")
                } header: {
                    Text("Unidad natural (opcional)")
                } footer: {
                    Text("Si la rellenas, podrás ajustar la cantidad en unidades en vez de en gramos.")
                }
            }
            .navigationTitle(isNew ? "Nuevo ingrediente" : "Editar ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(trimmedName.isEmpty || grams <= 0)
                }
            }
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(suffix, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(suffix)
                .foregroundStyle(.secondary)
        }
    }

    private func lookUp() {
        guard let analyzer else { return }
        let query = trimmedName
        isLookingUp = true
        lookUpError = nil
        Task {
            do {
                let found = try await analyzer.lookUp(foodName: query)
                name = found.name
                kcal = found.kcalPer100g
                protein = found.proteinPer100g
                carbs = found.carbsPer100g
                fat = found.fatPer100g
                if let unit = found.unitName, let perUnit = found.gramsPerUnit {
                    unitName = unit
                    gramsPerUnit = perUnit
                }
                // El peso solo se propone en un alta; al editar respetamos el que ya había.
                if isNew { grams = found.grams }
            } catch {
                lookUpError = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    private func save() {
        let unit = unitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasUnit = !unit.isEmpty && gramsPerUnit > 0
        onSave(FoodItem(id: existingID ?? UUID(),
                        name: trimmedName,
                        grams: grams,
                        unitName: hasUnit ? unit : nil,
                        gramsPerUnit: hasUnit ? gramsPerUnit : nil,
                        kcalPer100g: kcal,
                        proteinPer100g: protein,
                        carbsPer100g: carbs,
                        fatPer100g: fat))
        dismiss()
    }
}
```

Conservar `existingID` al editar es lo que evita que un ingrediente editado se duplique en la lista del borrador.

- [ ] **Step 2: Compilar**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyFit/Views/Meals/FoodItemFormView.swift MyFit.xcodeproj
git commit -m "feat: formulario de alta y edición manual de ingredientes"
```

---

### Task 10: `MealEditorView` — la pantalla de edición compartida

Ingredientes con peso ajustable, totales vivos y el campo de corrección encadenada. La usan tanto la captura como el detalle.

**Files:**
- Create: `MyFit/Views/Meals/MealEditorView.swift`

**Interfaces:**
- Consumes: `MealDraft` (Task 8), `FoodAnalyzer` (Task 6), `FoodItemFormView` (Task 9), `ImageStorage.preparedForUpload(_:)`.
- Produces: `struct MealEditorView: View` con `init(draft: MealDraft, analyzer: FoodAnalyzer?)`. Se coloca dentro de un `Form` propio, así que los padres solo la insertan.

- [ ] **Step 1: Crear la vista**

Crear `MyFit/Views/Meals/MealEditorView.swift`:

```swift
import SwiftUI

/// Edición de una comida: desglose por ingredientes, totales en vivo y corrección con IA.
/// Compartida por la captura de una comida nueva y la reedición de una guardada.
struct MealEditorView: View {
    @Bindable var draft: MealDraft
    /// nil si no hay proveedor de imágenes configurado: se oculta todo lo que llame a la IA.
    let analyzer: FoodAnalyzer?

    @State private var correctionText = ""
    @State private var isRefining = false
    @State private var refineError: String?
    @State private var editingItem: FoodItem?
    @State private var isAddingItem = false

    var body: some View {
        Form {
            if let photo = draft.photo {
                Section {
                    HStack {
                        Spacer()
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Plato") {
                TextField("Nombre del plato", text: $draft.name)
            }

            ingredientsSection
            totalsSection

            if analyzer != nil {
                correctionSection
            }
        }
        .sheet(isPresented: $isAddingItem) {
            FoodItemFormView(item: nil, analyzer: analyzer) { item in
                draft.items.append(item)
            }
        }
        .sheet(item: $editingItem) { item in
            FoodItemFormView(item: item, analyzer: analyzer) { updated in
                if let index = draft.items.firstIndex(where: { $0.id == updated.id }) {
                    draft.items[index] = updated
                }
            }
        }
    }

    // MARK: - Ingredientes

    private var ingredientsSection: some View {
        Section("Ingredientes") {
            ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                ingredientRow(item, at: index)
            }
            .onDelete { offsets in
                draft.items.remove(atOffsets: offsets)
            }

            if draft.items.isEmpty {
                Text("La IA no ha sabido desglosar este plato. Añade los ingredientes a mano o díselo en \"Corregir con IA\".")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                isAddingItem = true
            } label: {
                Label("Añadir ingrediente", systemImage: "plus.circle")
            }
        }
    }

    private func ingredientRow(_ item: FoodItem, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                editingItem = item
            } label: {
                HStack {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(Int(item.macros.kcal.rounded())) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Stepper {
                HStack {
                    Text(draft.quantityLabel(for: item))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    // Los gramos siempre a la vista, aunque se ajuste en unidades.
                    if item.hasUsableUnit {
                        Text("\(Int(item.grams.rounded())) g")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } onIncrement: {
                draft.adjustQuantity(at: index, by: 1)
            } onDecrement: {
                draft.adjustQuantity(at: index, by: -1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Totales

    private var totalsSection: some View {
        Section("Total") {
            let totals = draft.totals
            HStack {
                Text("\(Int(totals.kcal.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("kcal")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 16) {
                macroLabel("P", grams: totals.protein, color: .blue)
                macroLabel("C", grams: totals.carbs, color: .orange)
                macroLabel("G", grams: totals.fat, color: .yellow)
                Spacer()
            }
        }
    }

    private func macroLabel(_ letter: String, grams: Double, color: Color) -> some View {
        Text("\(letter) \(Int(grams.rounded()))g")
            .font(.subheadline)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Corrección con IA

    private var correctionSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("En realidad es…", text: $correctionText, axis: .vertical)
                    .lineLimit(1...4)
                    .disabled(isRefining)
                Button {
                    refine()
                } label: {
                    if isRefining {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(correctionText.trimmingCharacters(in: .whitespaces).isEmpty || isRefining)
            }

            if let refineError {
                Text(refineError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !draft.corrections.isEmpty {
                DisclosureGroup("Ya le has dicho (\(draft.corrections.count))") {
                    ForEach(Array(draft.corrections.enumerated()), id: \.offset) { _, correction in
                        Text("· \(correction.text)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Corregir con IA")
        } footer: {
            Text("Cada corrección se suma a las anteriores: la IA recuerda todo lo que le has dicho sobre este plato.")
        }
    }

    private func refine() {
        let text = correctionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let analyzer else { return }

        let history = draft.corrections + [FoodCorrection(text: text)]
        let current = draft.analysis
        let imageData = draft.photo.flatMap(ImageStorage.preparedForUpload)

        isRefining = true
        refineError = nil
        Task {
            do {
                let result = try await analyzer.analyze(imageData: imageData,
                                                        current: current,
                                                        corrections: history)
                draft.apply(result)
                draft.corrections = history
                correctionText = ""
            } catch {
                // El desglose actual se queda intacto y el texto NO se borra:
                // un timeout no puede hacerte perder lo que acabas de escribir.
                refineError = error.localizedDescription
            }
            isRefining = false
        }
    }
}
```

- [ ] **Step 2: Compilar**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MyFit/Views/Meals/MealEditorView.swift MyFit.xcodeproj
git commit -m "feat: MealEditorView con pesos ajustables y corrección encadenada"
```

---

### Task 11: La captura usa el editor de ingredientes

Se sustituyen los cinco `@State` planos de `MealCaptureView` por un `MealDraft` y su formulario por `MealEditorView`.

**Files:**
- Modify: `MyFit/Views/Meals/MealCaptureView.swift`

**Interfaces:**
- Consumes: `MealDraft` (Task 8), `MealEditorView` (Task 10), `FoodAnalyzer` + `AIServiceResolver.makeFoodAnalyzer()` (Task 6).
- Produces: nada nuevo hacia fuera.

- [ ] **Step 1: Cambiar el estado de la vista**

En `MyFit/Views/Meals/MealCaptureView.swift`, sustituir el bloque de `@State` (las cinco variables `name`, `calories`, `protein`, `carbs`, `fat`) por:

```swift
    @State private var draft = MealDraft()
```

`image` se conserva: la fase `.analyzing` la muestra antes de que exista desglose.

- [ ] **Step 2: Sustituir `editForm` por el editor**

Borrar por completo `editForm` y `macroRow(title:value:)`, y cambiar el `case .editing` del `switch` por:

```swift
                case .editing:
                    MealEditorView(draft: draft, analyzer: AIServiceResolver.makeFoodAnalyzer())
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                save()
                            } label: {
                                Text("Guardar comida")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                                      || draft.items.isEmpty)
                            .padding()
                            .background(.bar)
                        }
```

El botón sale del `Form` y pasa a una barra inferior fija porque el formulario ahora es largo: con el desglose y el campo de corrección, un botón al final de la lista se queda fuera de pantalla.

- [ ] **Step 3: Volcar el análisis en el borrador**

En `analyze()`, sustituir el bloque del `Task` por:

```swift
        Task {
            do {
                let result = try await analyzer.analyze(imageData: data, current: nil, corrections: [])
                draft.photo = image
                draft.apply(result)
                phase = .editing
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
```

- [ ] **Step 4: Guardar desde el borrador**

Sustituir `save()` por:

```swift
    private func save() {
        var fileName: String?
        if let image {
            fileName = try? ImageStorage.save(image)
        }
        let meal = Meal(name: "", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0,
                        photoFileName: fileName)
        draft.save(into: meal)
        context.insert(meal)
        dismiss()
    }
```

`draft.save(into:)` rellena nombre, desglose, correcciones y los cuatro totales recalculados.

- [ ] **Step 5: Compilar y probar a mano**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

Prueba manual en el simulador, con una API key configurada en Ajustes:

1. Elegir una foto de comida de la galería.
2. Comprobar que aparece el desglose por ingredientes con pesos.
3. Subir el peso de un ingrediente: las kcal totales deben cambiar **al instante**, sin spinner.
4. Escribir una corrección ("no es queso crema, es queso fresco batido con dos huevos") y enviarla: el desglose se rehace y la corrección aparece en "Ya le has dicho".
5. Añadir un ingrediente a mano y usar "Buscar macros con IA".
6. Guardar y comprobar que la comida sale en la lista con las kcal correctas.

- [ ] **Step 6: Commit**

```bash
git add MyFit/Views/Meals/MealCaptureView.swift
git commit -m "feat: la captura de comida usa el editor de ingredientes"
```

---

### Task 12: Reeditar una comida guardada

Cierra el círculo: tocar una comida de la lista la abre en el mismo editor.

**Files:**
- Create: `MyFit/Views/Meals/MealDetailView.swift`
- Modify: `MyFit/Views/Meals/MealListView.swift:100-111` (el `ForEach` de las comidas)

**Interfaces:**
- Consumes: `MealDraft(meal:photo:)` (Task 8), `MealEditorView` (Task 10), `ImageStorage.load(fileName:)`.
- Produces: `struct MealDetailView: View` con `init(meal: Meal)`.

- [ ] **Step 1: Crear la vista de detalle**

Crear `MyFit/Views/Meals/MealDetailView.swift`:

```swift
import SwiftUI
import SwiftData

/// Reedición de una comida ya guardada, sobre el mismo editor que la captura.
struct MealDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let meal: Meal
    @State private var draft: MealDraft

    init(meal: Meal) {
        self.meal = meal
        let photo = meal.photoFileName.flatMap(ImageStorage.load(fileName:))
        _draft = State(initialValue: MealDraft(meal: meal, photo: photo))
    }

    var body: some View {
        MealEditorView(draft: draft, analyzer: AIServiceResolver.makeFoodAnalyzer())
            .navigationTitle("Editar comida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        draft.save(into: meal)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.items.isEmpty)
                }
            }
    }
}
```

Salir sin pulsar "Guardar" descarta los cambios: el `MealDraft` es una copia, no toca el `Meal` hasta el `save(into:)`.

- [ ] **Step 2: Enlazar desde la lista**

En `MyFit/Views/Meals/MealListView.swift`, envolver `MealRow` en un `NavigationLink` dentro del `ForEach`, dejando el `swipeActions` donde está:

```swift
                            ForEach(group.meals) { meal in
                                NavigationLink {
                                    MealDetailView(meal: meal)
                                } label: {
                                    MealRow(meal: meal)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if let fileName = meal.photoFileName {
                                            ImageStorage.delete(fileName: fileName)
                                        }
                                        context.delete(meal)
                                    } label: {
                                        Label("Borrar", systemImage: "trash")
                                    }
                                }
                            }
```

- [ ] **Step 3: Compilar y probar a mano**

```bash
xcodegen generate
xcodebuild -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -20
```

Esperado: `** BUILD SUCCEEDED **`.

Prueba manual, encadenada con la de la Task 11:

1. Tocar la comida guardada: se abre con su desglose y su foto.
2. Cambiar un peso, guardar, y comprobar que las kcal del día en la tarjeta "Hoy" cambian en consecuencia.
3. Volver a entrar y escribir otra corrección: en "Ya le has dicho" deben salir **también las de la sesión anterior**, que es lo que prueba que el historial se persistió.
4. Abrir una comida **antigua** sin desglose (la guardada en la Task 7, Step 3): debe mostrar un ingrediente único con sus totales y ser editable sin romperse.
5. Comprobar que el deslizar-para-borrar sigue funcionando en la lista.

- [ ] **Step 4: Commit**

```bash
git add MyFit/Views/Meals/MealDetailView.swift MyFit/Views/Meals/MealListView.swift MyFit.xcodeproj
git commit -m "feat: reedición de comidas guardadas desde la lista"
```

---

## Verificación final

- [ ] **Suite completa en verde**

```bash
xcodegen generate
xcodebuild test -project MyFit.xcodeproj -scheme MyFit \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30
```

- [ ] **Los cinco proveedores siguen respondiendo**

Esto **no es automatizable aquí**: requiere las API keys reales en el dispositivo. Para cada proveedor configurado en Ajustes (OpenAI, Claude, Kimi, NVIDIA, Gemini), analizar una foto de comida y comprobar que devuelve desglose. Es la verificación que cubre el riesgo del refactor de las Tasks 2 y 3; los tres proveedores unificados en `OpenAICompatibleService` (OpenAI, Kimi, NVIDIA) son los más expuestos.

Si un proveedor devuelve totales pero no desglosa (esperable en `meta/llama-3.2-11b-vision-instruct`), **no es un fallo**: debe aparecer el ingrediente único de reserva. Un fallo es un error de red, un JSON no decodificable o una app que peta.

- [ ] **Actualizar el README**

`README.md` describe la sección "Comida" como "la IA estima calorías y macros automáticamente" y lista 4 proveedores cuando ya son 5. Actualizar la sección de características para reflejar el desglose por ingredientes, la corrección conversacional y los pesos editables, y añadir Gemini a la lista de proveedores.

```bash
git add README.md
git commit -m "docs: actualiza el README con el desglose por ingredientes"
```
