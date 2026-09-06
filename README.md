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
- Fotografía tu comida y la IA estima calorías y macros automáticamente
- Barra de progreso diaria de calorías vs objetivo
- Desglose de macros (proteína, carbohidratos, grasa) con progreso vs objetivos
- Objetivos calculados desde tu metabolismo basal en Apple Salud o ajustables manualmente

### Asistente NutriCoach
- Chat nutricional con IA consciente de la fecha, hora y momento del día
- Adapta las sugerencias a tus objetivos calóricos configurados
- Cancela la respuesta en cualquier momento con el botón de parar

### Ajustes
- Soporte para 4 proveedores de IA: **OpenAI**, **Claude (Anthropic)**, **Kimi (Moonshot)** y **NVIDIA NIM**
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
| Kimi | `kimi-k2.6` | Modelo de razonamiento |
| NVIDIA NIM | `moonshotai/kimi-k2.6` | Kimi en infraestructura NVIDIA |

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
├── Models/          # SwiftData models (Workout, WeightEntry, Meal)
├── Services/        # Lógica de negocio
│   ├── AIService    # Protocolo y resolución de proveedor
│   ├── KimiService / OpenAIService / ClaudeService / NvidiaService
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
