import SwiftUI
import SwiftData

struct MealCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case pick
        case analyzing
        case editing
        case failed(String)
    }

    @State private var phase: Phase = .pick
    @State private var pickerSource: ImagePicker.Source?
    @State private var image: UIImage?

    @State private var name = ""
    @State private var calories = 0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick:
                    pickView
                case .analyzing:
                    VStack(spacing: 16) {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 240)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        ProgressView("Analizando tu comida con IA…")
                    }
                    .padding()
                case .editing:
                    editForm
                case .failed(let message):
                    VStack(spacing: 16) {
                        ContentUnavailableView("No se pudo analizar",
                                               systemImage: "exclamationmark.triangle",
                                               description: Text(message))
                        Button("Reintentar") { analyze() }
                            .buttonStyle(.borderedProminent)
                        Button("Elegir otra foto") { phase = .pick }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .navigationTitle("Nueva comida")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard phase == .pick,
                      UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                pickerSource = .camera
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .sheet(item: $pickerSource) { source in
                ImagePicker(source: source) { picked in
                    pickerSource = nil
                    image = picked
                    analyze()
                } onCancel: {
                    pickerSource = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private var pickView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Fotografía tu comida para estimar sus calorías y macros.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    pickerSource = .camera
                } label: {
                    Label("Hacer foto", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                pickerSource = .photoLibrary
            } label: {
                Label("Elegir de la galería", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var editForm: some View {
        Form {
            if let image {
                Section {
                    HStack {
                        Spacer()
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Resultado (puedes corregirlo)") {
                TextField("Nombre del plato", text: $name)
                Stepper("Calorías: \(calories) kcal", value: $calories, in: 0...5000, step: 10)
                macroRow(title: "Proteína", value: $protein)
                macroRow(title: "Carbohidratos", value: $carbs)
                macroRow(title: "Grasa", value: $fat)
            }

            Section {
                Button {
                    save()
                } label: {
                    Text("Guardar comida")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func macroRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("g", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("g")
                .foregroundStyle(.secondary)
        }
    }

    private func analyze() {
        guard let image,
              let service = AIServiceResolver.makeService(),
              let data = ImageStorage.preparedForUpload(image) else {
            phase = .failed("No hay una API key configurada o la imagen no es válida.")
            return
        }
        phase = .analyzing
        Task {
            do {
                let result = try await service.analyzeFood(imageData: data)
                name = result.name
                calories = result.calories
                protein = result.protein
                carbs = result.carbs
                fat = result.fat
                phase = .editing
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func save() {
        var fileName: String?
        if let image {
            fileName = try? ImageStorage.save(image)
        }
        let meal = Meal(name: name.trimmingCharacters(in: .whitespaces),
                        calories: calories,
                        proteinGrams: protein,
                        carbsGrams: carbs,
                        fatGrams: fat,
                        photoFileName: fileName)
        context.insert(meal)
        dismiss()
    }
}
