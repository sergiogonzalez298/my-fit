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
        let item = try JSONDecoder().decode(FoodItem.self,
                                            from: AIServicePrompt.extractJSON(from: text))
        // El decodificador de FoodItem nunca lanza (lo necesita SwiftData para releer datos
        // guardados): sin este filtro, un valor inventado llegaría tal cual al formulario.
        guard item.isPlausible else { throw AIServiceError.invalidResponse }
        return item
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
        - grams: peso en gramos de ESE ingrediente en UNA ración, la que se ha comido una \
        persona, no la receta completa. Es el fallo más fácil cuando solo hay una descripción: \
        una receta de salmorejo lleva un kilo de tomate y da para cuatro, pero un plato lleva \
        unos 250 g. Si la descripción no da cantidades, estima una ración normal de una persona.
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
            if current == nil {
                // Primer análisis: esto no son correcciones, es la única descripción del
                // plato. Presentarlo como corrección entierra el enunciado en una sección
                // que la IA lee como ajustes sobre un análisis anterior inexistente.
                prompt += """


                DESCRIPCIÓN DEL USUARIO, en orden:
                \(list)

                Es lo que ha comido. Desglósalo en ingredientes con las cantidades de UNA ración.
                """
            } else {
                prompt += """


                CORRECCIONES DEL USUARIO, en orden:
                \(list)

                Aplica TODAS las correcciones, no solo la última, y devuelve el desglose completo corregido.
                """
            }
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
