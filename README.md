# MyFit

App iOS de seguimiento fitness con análisis nutricional por IA y sincronización con Apple Salud.

## Características

### Entrenos
- Importación automática desde Apple HealthKit (compatible con Spediance y cualquier app que escriba en Salud)
- Lista con colores por tipo de entreno (fuerza, cardio, movilidad, deporte)
- Estadísticas semanales: número de sesiones y calorías quemadas
- Sincronización automática al abrir la app

### Peso y composición corporal
- Historial con gráfica de evolución
- Importación desde Apple Salud: peso, % de grasa, masa muscular y BMI
- Posibilidad de borrar y reimportar todo el historial

### Comida
- Fotografía tu comida y la IA la analiza ingrediente por ingrediente, con el peso y las macros por 100g de cada uno
- Edita el peso de cualquier ingrediente y las macros se recalculan al instante, sin necesidad de llamar a la IA; los ingredientes con unidad natural (huevos, cucharadas, rebanadas) se ajustan en esa unidad, manteniendo siempre visibles los gramos
- Corrige el análisis escribiendo en lenguaje natural lo que realmente hay en el plato (por ejemplo "no es queso crema, es queso fresco batido con dos huevos"); la IA rehace el desglose teniendo en cuenta todas las correcciones anteriores y respetando los pesos que hayas ajustado a mano
- Añade, edita o elimina ingredientes manualmente, con un atajo opcional para que la IA complete las macros por 100g a partir del nombre del alimento
- Las comidas guardadas se pueden reabrir y editar de nuevo, con sus ingredientes y su historial de correcciones intactos; las comidas guardadas antes de esta función se abren como un único ingrediente con sus totales, así que también son editables
- Barra de progreso diaria de calorías vs objetivo
- Desglose de macros (proteína, carbohidratos, grasa) con progreso vs objetivos
- Objetivos calculados desde tu metabolismo basal en Apple Salud o ajustables manualmente

### Asistente NutriCoach
- Chat nutricional con IA consciente de la fecha, hora y momento del día
- Adapta las sugerencias a tus objetivos calóricos configurados
- Cancela la respuesta en cualquier momento con el botón de parar

### Ajustes
- Soporte para 5 proveedores de IA: **OpenAI**, **Claude (Anthropic)**, **Gemini (Google)**, **Kimi (Moonshot)** y **NVIDIA NIM**
- API keys guardadas de forma segura en el Keychain del dispositivo
- Modelo de IA configurable por proveedor
- Diagnóstico de conexión integrado

## Requisitos

- iOS 17+
- Xcode 15+
- API key de alguno de los proveedores de IA soportados

## Modelos recomendados

| Proveedor | Modelo por defecto | Notas |
|---|---|---|
| OpenAI | `gpt-4o-mini` | Rápido y económico |
| Claude | `claude-sonnet-4-6` | Alta calidad |
| Gemini | `gemini-3.5-flash-lite` | Rápido y económico |
| Kimi | `kimi-k2.6` | Modelo de razonamiento |
| NVIDIA NIM | `openai/gpt-oss-20b` | Modelo abierto en infraestructura NVIDIA |

## Instalación

1. Clona el repositorio
2. Instala [XcodeGen](https://github.com/yonaskolb/XcodeGen) si no lo tienes: `brew install xcodegen`
3. Genera el proyecto: `xcodegen generate`
4. Abre `MyFit.xcodeproj` en Xcode
5. Selecciona tu equipo de desarrollo en *Signing & Capabilities*
6. Ejecuta en tu dispositivo

## Configuración inicial

1. Abre la app y ve a **Ajustes**
2. Selecciona tu proveedor de IA preferido
3. Introduce tu API key (se guarda en el Keychain)
4. Permite el acceso a Apple Salud cuando la app lo solicite
5. Tus entrenos y peso se importarán automáticamente

## Permisos requeridos

- **Apple Salud** — lectura de entrenamientos, peso, composición corporal y metabolismo basal
- **Cámara** — fotografiar comidas para análisis nutricional
- **Galería de fotos** — elegir imágenes existentes para análisis

## Arquitectura

```
MyFit/
├── Models/          # SwiftData models (Workout, WeightEntry, Meal, FoodItem, FoodAnalysis, Macros)
├── Services/        # Lógica de negocio
│   ├── AIService    # Protocolo y resolución de proveedor
│   ├── OpenAICompatibleService (OpenAI, Kimi, NVIDIA) / ClaudeService / GeminiService
│   ├── FoodAnalyzer # Lógica de análisis de comida sobre el transporte de IA
│   ├── HealthKitService
│   ├── SyncService
│   ├── NutritionChatService
│   └── ImageStorage / KeychainHelper
└── Views/
    ├── Workouts/
    ├── Weight/
    ├── Meals/
    ├── Assistant/
    └── Settings/
```

- **SwiftUI + SwiftData** (iOS 17+)
- **HealthKit** para datos de salud y fitness
- **Keychain** para almacenamiento seguro de API keys
- APIs de IA en formato compatible con OpenAI

## Licencia

MIT
