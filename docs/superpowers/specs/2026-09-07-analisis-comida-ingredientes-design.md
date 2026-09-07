# Análisis de comida por ingredientes, corrección conversacional y pesos editables

Fecha: 2026-09-07
Estado: aprobado, pendiente de plan de implementación

## Problema

El análisis de una foto de comida devuelve hoy un único bloque plano —nombre, kcal y tres macros— que el usuario solo puede corregir sobreescribiendo los cuatro números a mano.

Cuando la IA identifica mal el plato, esa corrección es inviable en la práctica. Ejemplo real: en una foto la IA ve "pan con queso crema", cuando lo que hay es pan con una falsa mayonesa de queso fresco batido y dos huevos hervidos. Los macros no se parecen, y el usuario no tiene forma de decírselo ni de saber de qué peso salieron los números.

Faltan tres cosas:

1. Poder decirle a la IA en lenguaje natural qué hay realmente en el plato.
2. Ver el desglose por ingredientes con el peso que la IA asume para cada uno.
3. Cambiar esos pesos y que los macros se recalculen.

## Decisiones de producto

| Decisión | Elección |
|---|---|
| Corrección | Híbrida: el texto va a la IA; los pesos se recalculan en local, al instante |
| Refinado | Conversación encadenada — cada corrección conserva las anteriores |
| Persistencia | El desglose se guarda y la comida guardada se puede reeditar |
| Edición manual | Completa: añadir, editar y borrar ingredientes sin pasar por la IA |
| Unidades | Gramos + unidades naturales ("2 uds", "½ cucharada"), gramos como fuente de verdad |

La decisión híbrida es la que fija el contrato con la IA: para recalcular en local hace falta que cada ingrediente traiga sus **macros por 100 g**, no solo su aportación a la porción.

## Arquitectura

### Modelo de datos

Tres tipos nuevos en `MyFit/Models/`:

```swift
/// Totales nutricionales. Un solo tipo para dejar de arrastrar 4 campos sueltos.
struct Macros: Codable, Hashable {
    var kcal, protein, carbs, fat: Double
    static let zero: Macros
    static func + (lhs: Macros, rhs: Macros) -> Macros
}

/// Un alimento dentro de una comida.
/// Los GRAMOS son la fuente de verdad; la unidad natural solo es una forma cómoda de editarlos.
struct FoodItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var grams: Double

    var unitName: String?       // "ud", "cucharada", "rebanada" — nil si no aplica
    var gramsPerUnit: Double?   // 55 — debe ser > 0 cuando hay unitName

    // Macros POR 100 g: lo que permite recalcular en local al mover el peso
    var kcalPer100g, proteinPer100g, carbsPer100g, fatPer100g: Double

    var macros: Macros { /* per100g * grams / 100 */ }
    var units: Double? { get set }   // grams / gramsPerUnit; al escribir, grams = units * gramsPerUnit
                                     // nil, y escribir no hace nada, si gramsPerUnit es nil o <= 0
}

/// Lo que el usuario le ha dicho a la IA sobre esta comida, en orden.
struct FoodCorrection: Codable, Hashable { var text: String; var date: Date }
```

`FoodAnalysis` pierde los macros planos:

```swift
struct FoodAnalysis: Codable {
    var name: String
    var items: [FoodItem]
    /// Totales que dio la IA cuando no supo desglosar. Solo se usan si `items` está vacío.
    var fallbackTotals: Macros?
    var totals: Macros { items.isEmpty ? (fallbackTotals ?? .zero) : items.map(\.macros).reduce(.zero, +) }
}
```

### Persistencia

`Meal` gana dos propiedades y **conserva** las cuatro planas:

```swift
var items: [FoodItem] = []              // nuevo
var corrections: [FoodCorrection] = []  // nuevo
var calories: Int                       // se mantiene: recalculado desde items al guardar
var proteinGrams, carbsGrams, fatGrams: Double
```

Mantener los totales desnormalizados es deliberado. `MealListView` agrega con `meals.map(\.calories).reduce(...)`, `NutritionChatService` construye su prompt con ellos y `SyncService` los usa: dejándolos ahí, ese código no se toca. Se recalculan desde `items` en cada guardado. Solo quedan como valor editable a mano en las comidas
antiguas que siguen con `items` vacío y sin foto, donde no hay desglose del que derivarlos.

Dos detalles del terreno:

- SwiftData sí guarda arrays de structs `Codable`. Precedente en el repo: `Recipe.ingredientSections: [RecipeSection]`.
- `corrections` es `[FoodCorrection]` y no `[String]` a propósito: `Recipe` documenta que `Array<String>` da problemas de bridging con CoreData y lo esquiva con `mealSlotsRaw`. No se repite ese apaño.
- Migración: cambio aditivo con valores por defecto. Las comidas ya guardadas quedan con `items: []`, conservan sus totales y se siguen viendo igual que hoy.

### Capa de IA

El protocolo se reduce a transporte puro:

```swift
protocol AIService: Sendable {
    /// Envía un prompt (con imagen opcional) y devuelve el texto crudo de la respuesta.
    func complete(prompt: String, imageData: Data?) async throws -> String
}
```

De 5 servicios a 3. `OpenAICompatibleService` absorbe OpenAI, Kimi y NVIDIA —los tres hablan `chat/completions`— parametrizado por `baseURL`, `timeout`, si envía `response_format: json_object`, y un preprocesado opcional de imagen. Con eso NVIDIA conserva su compresión a 512 px y Kimi su timeout de 120 s. `ClaudeService` y `GeminiService` mantienen su mapeo propio.

Encima, un único `FoodAnalyzer` con toda la lógica de comida (prompts, esquema JSON, decodificación, validación):

```swift
struct FoodAnalyzer {
    let service: any AIService
    /// Primer análisis y refinado son la misma llamada: `current` nil = primera vez.
    func analyze(imageData: Data?, current: FoodAnalysis?, corrections: [FoodCorrection]) async throws -> FoodAnalysis
    /// Macros por 100 g de un alimento suelto — el atajo al añadir a mano.
    func lookUp(foodName: String) async throws -> FoodItem
}
```

Motivo del refactor: la función pedida necesita **dos** operaciones de IA. Con la estructura actual —cada servicio duplicando "construir payload → POST → comprobar status → decodificar → extraer JSON"— serían diez bloques casi idénticos. Está acotado: `AIService.analyzeFood` lo consume un solo sitio, `MealCaptureView.swift:175`. `RecipeGeneratorService` y `NutritionChatService` hacen su propio HTTP y quedan fuera de este trabajo.

**Refinado sobre el estado en pantalla.** Al refinar se envía el desglose que hay en pantalla en ese momento, no lo que la IA contestó la última vez. Si el usuario subió el pan a 80 g a mano y luego escribe "el pan es de centeno", la IA corrige sobre esos 80 g en vez de pisarlos.

**Regla explícita en el prompt.** Los valores por 100 g son de tabla, sin escalar a la porción; el peso va aparte en `grams`. Es el fallo típico de los modelos en este esquema.

Esquema de respuesta:

```json
{"name": "Tostada de pan integral con queso fresco y huevo",
 "items": [{"name": "Huevo cocido", "grams": 110, "unitName": "ud", "gramsPerUnit": 55,
            "kcalPer100g": 155, "proteinPer100g": 13, "carbsPer100g": 1.1, "fatPer100g": 11}]}
```

### UI

Un estado compartido y una vista de edición compartida, para que fotografiar una comida nueva y reeditar una guardada sean la misma pantalla:

```swift
@Observable final class MealDraft {
    var name: String
    var items: [FoodItem]
    var corrections: [FoodCorrection]
    var photo: UIImage?
    var totals: Macros { items.map(\.macros).reduce(.zero, +) }
}
```

`MealDraft` siempre tiene al menos un ingrediente: si `FoodAnalysis` llega sin `items` pero con
`fallbackTotals`, al construir el draft se sintetiza un `FoodItem` único con el nombre de la comida,
`grams: 100` y los totales como macros por 100 g. Así `totals` es siempre la suma de `items` y no
hace falta un segundo camino de cálculo en la UI.

**`MealEditorView`** (nueva, compartida) — foto, nombre editable, lista de ingredientes, totales vivos y campo de corrección:

```
┌──────────────────────────────────┐
│            [ foto ]              │
│  Nombre  [Tostada de pan integ.] │
│                                  │
│  INGREDIENTES                    │
│  Pan integral                    │
│    2 rebanadas   [– +]     60 g ›│  ← tocar = editar ficha
│  Queso fresco batido             │
│    100 g         [– +]    100 g ›│
│  Huevo cocido                    │
│    2 uds         [– +]    110 g ›│  ← deslizar = borrar
│  + Añadir ingrediente            │
│                                  │
│  TOTAL                           │
│  412 kcal · P 32 · C 34 · G 16   │  ← recálculo instantáneo
│                                  │
│  CORREGIR CON IA                 │
│  [en realidad es queso fres…] [→]│
│  Ya le has dicho:                │
│   · "no es queso crema, es…"     │
│   · "el pan es de centeno"       │
└──────────────────────────────────┘
```

El stepper edita **unidades** si el ingrediente tiene unidad natural y gramos si no; los gramos resultantes siempre se ven a la derecha. El historial de correcciones va visible y colapsable: al ser conversación encadenada, el usuario tiene que poder ver qué contexto lleva la IA.

**`FoodItemFormView`** (nueva, sheet) — añadir o editar un ingrediente a mano: nombre, peso, unidad natural opcional (nombre + gramos por unidad) y los cuatro macros por 100 g. Arriba, el atajo que evita teclearlos: **"Buscar macros con IA"** llama a `FoodAnalyzer.lookUp(foodName:)` con el nombre escrito y rellena los cuatro campos, que quedan editables.

**`MealCaptureView`** — mantiene sus fases `pick → analyzing → editing → failed`; la fase `editing` pasa a ser `MealEditorView` sobre un `MealDraft`. Al guardar, recalcula los totales planos desde `items`.

**`MealDetailView`** (nueva) — misma `MealEditorView`, cargando el `MealDraft` desde un `Meal` existente. Guardado explícito con un botón "Guardar" en la
barra; salir sin guardar descarta los cambios, igual que en la captura. En `MealListView` la fila pasa a ser `NavigationLink`; el deslizar-para-borrar actual se queda igual.

## Flujo de datos

```
Foto ──► FoodAnalyzer.analyze(imageData:current:nil, corrections:[])
              │
              ▼
       FoodAnalysis(items:[…])  ──►  MealDraft
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
            editar peso/unidad   añadir/borrar ítem   escribir corrección
                    │                   │                   │
                    │  (local, instantáneo)                 ▼
                    │                   │      FoodAnalyzer.analyze(
                    │                   │        imageData:, current: draft,
                    │                   │        corrections: draft.corrections + nueva)
                    │                   │                   │
                    └───────────────────┴───────────────────┘
                                        │
                                        ▼
                              draft.totals (recálculo)
                                        │
                                   [Guardar]
                                        │
                                        ▼
                     Meal(items:, corrections:, + totales planos)
```

## Casos límite

- **La IA no desglosa** (probable con `llama-3.2-11b` de NVIDIA): se usa `fallbackTotals`, se muestra una fila única no desglosada y un aviso de que puede desglosarse escribiéndole.
- **El refinado falla**: el desglose actual queda intacto, la corrección no se borra del campo y sale un banner de error. Un timeout nunca pierde trabajo.
- **Comidas antiguas** (`items` vacío): el detalle muestra los totales editables a mano y, si la comida tiene foto, un botón "desglosar en ingredientes con IA".
- **Sin foto**: `analyze(imageData:)` acepta `nil` y refina solo con texto. Es lo que mantiene corregible una comida antigua sin foto. Registrar comida sin foto queda fuera de alcance, pero el contrato no lo impide.
- **Unidad incoherente** (`unitName` sin `gramsPerUnit`, o `gramsPerUnit <= 0`): se ignora la unidad y la fila cae a gramos.
- **Valores absurdos de la IA**: validación de rango al decodificar —gramos y macros no negativos, per-100 g dentro de límites físicos—. Descartar un ingrediente malo es preferible a guardar 9.000 kcal.

## Testing

El corazón del cambio es aritmética pura y decodificación, que es justo lo que conviene tener bajo test:

- `FoodItem.macros` para pesos varios.
- Conversión unidades ↔ gramos en los dos sentidos, incluida la unidad incoherente.
- Suma de totales, incluida la lista vacía.
- Decodificación del JSON de la IA, con casos degenerados: sin `items`, con unidad rota, con negativos, con `fallbackTotals`.
- Ensamblado del prompt de refinado: que incluya el desglose actual y todas las correcciones en orden.

Hace falta un target de tests, que hoy no existe: un bloque `MyFitTests` en `project.yml` y regenerar con XcodeGen. Se usa **Swift Testing** (`@Test`), nativo en el target iOS 17 del proyecto.

Ningún test toca la red: los de `FoodAnalyzer` usan un `AIService` falso que devuelve un texto fijo, que es precisamente lo que habilita el refactor a transporte puro.

**Verificación manual requerida (no automatizable aquí):** que los 5 proveedores siguen respondiendo correctamente tras el refactor. Requiere las API keys reales en dispositivo.

## Fuera de alcance

- Base de datos local de alimentos: los macros por 100 g los aporta la IA o el usuario.
- Registrar una comida sin foto como flujo de entrada.
- Refactorizar el HTTP propio de `RecipeGeneratorService` y `NutritionChatService`.
- Editar los totales de comidas antiguas más allá de lo que ya permite la edición manual.
