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

    private func analyze() {
        guard let image,
              let analyzer,
              let data = ImageStorage.preparedForUpload(image) else {
            phase = .failed("No hay una API key configurada o la imagen no es válida.")
            return
        }
        phase = .analyzing
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
