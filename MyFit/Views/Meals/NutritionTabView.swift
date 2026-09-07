import SwiftUI

/// Contenedor de la pestaña Comida: Hoy (registro), Plan semanal y Recetas.
/// Cada segmento lleva su propio NavigationStack para conservar sus títulos.
struct NutritionTabView: View {
    @Binding var selectedTab: Int
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $segment) {
                Text("Hoy").tag(0)
                Text("Plan").tag(1)
                Text("Recetas").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            switch segment {
            case 1:
                MealPlanView()
            case 2:
                NavigationStack {
                    RecipeListView()
                }
            default:
                MealListView(selectedTab: $selectedTab)
            }
        }
    }
}
