import SwiftUI
import SwiftData

struct MealCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case pick
        case describing
        case analyzing
        case editing
        case failed(String)
    }

    @State private var phase: Phase = .pick
    @State private var pickerSource: ImagePicker.Source?
    @State private var image: UIImage?
    @State private var mealDescription = ""

    @State private var draft = MealDraft()
    // Se resuelve una sola vez: llamarlo desde `body` repetiría la lectura del Keychain
    // en cada re-render (incluida cada pulsación de tecla en el nombre del plato).
    @State private var analyzer = AIServiceResolver.makeFoodAnalyzer()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick:
                    pickView
                case .describing:
                    describeView
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
                    MealEditorView(draft: draft, analyzer: analyzer)
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
                case .failed(let message):
                    VStack(spacing: 16) {
                        ContentUnavailableView("No se pudo analizar",
                                               systemImage: "exclamationmark.triangle",
                                               description: Text(message))
                        Button("Reintentar") { analyze() }
                            .buttonStyle(.borderedProminent)
                        Button("Empezar de nuevo") { startOver() }
                            .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
            .navigationTitle("Nueva comida")
            .navigationBarTitleDisplayMode(.inline)
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
            Text("Fotografía tu comida o descríbela con palabras para estimar sus calorías y macros.")
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
            Button {
                phase = .describing
            } label: {
                Label("Describir por texto", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var describeView: some View {
        Form {
            Section {
                TextField("Dos huevos revueltos, una tostada de centeno y medio aguacate",
                          text: $mealDescription, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("¿Qué has comido?")
            } footer: {
                Text("Cuanto más concreto seas con las cantidades y la preparación, mejor será la estimación.")
            }

            Section {
                Button {
                    analyze()
                } label: {
                    Text("Analizar")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .disabled(trimmedDescription.isEmpty)

                Button("Volver") { startOver() }
            }
        }
    }

    private var trimmedDescription: String {
        mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vuelve a la elección de método descartando lo introducido antes.
    ///
    /// `analyze()` lee `image` y `mealDescription` sin distinguir de qué intento vienen,
    /// así que arrastrarlos contaminaría el siguiente: una foto que falló seguiría
    /// adjunta al enviar después solo texto, y una descripción abandonada aparecería
    /// como corrección fantasma de una foto nueva.
    private func startOver() {
        image = nil
        mealDescription = ""
        phase = .pick
    }

    private func analyze() {
        guard let analyzer else {
            phase = .failed("No hay una API key configurada.")
            return
        }
        let imageData = image.flatMap(ImageStorage.preparedForUpload)
        if image != nil, imageData == nil {
            phase = .failed("No se pudo preparar la imagen.")
            return
        }
        guard imageData != nil || !trimmedDescription.isEmpty else {
            phase = .failed("No hay ni foto ni descripción que analizar.")
            return
        }

        // La descripción inicial viaja como primera corrección, no como un parámetro
        // aparte: así queda en el historial del borrador y la IA la sigue teniendo
        // delante en cada refinado posterior, en vez de perderla tras el primer análisis.
        let corrections = trimmedDescription.isEmpty ? [] : [FoodCorrection(text: trimmedDescription)]

        phase = .analyzing
        Task {
            do {
                let result = try await analyzer.analyze(imageData: imageData,
                                                        current: nil,
                                                        corrections: corrections)
                draft.photo = image
                draft.corrections = corrections
                draft.apply(result)
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
        let meal = Meal(name: "", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0,
                        photoFileName: fileName)
        draft.save(into: meal)
        context.insert(meal)
        dismiss()
    }
}
