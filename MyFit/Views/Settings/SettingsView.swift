import SwiftUI

struct SettingsView: View {
    @Binding var selectedTab: Int
    @AppStorage(AIServiceResolver.providerDefaultsKey) private var providerRaw: String = AIProvider.openai.rawValue
    @AppStorage(AIServiceResolver.imageProviderDefaultsKey) private var imageProviderRaw: String = ""
    @AppStorage(AIProvider.openai.modelDefaultsKey) private var openaiModel: String = ""
    @AppStorage(AIProvider.claude.modelDefaultsKey) private var claudeModel: String = ""
    @AppStorage("kimiModel") private var kimiModel: String = ""
    @AppStorage("nvidiaModel") private var nvidiaModel: String = ""
    @AppStorage("geminiModel") private var geminiModel: String = ""
    @AppStorage("openaiVisionModel") private var openaiVisionModel: String = ""
    @AppStorage("claudeVisionModel") private var claudeVisionModel: String = ""
    @AppStorage("kimiVisionModel") private var kimiVisionModel: String = ""
    @AppStorage("nvidiaVisionModel") private var nvidiaVisionModel: String = ""
    @AppStorage("geminiVisionModel") private var geminiVisionModel: String = ""

    @AppStorage(SyncService.calorieGoalKey) private var calorieGoal: Int = 2000
    @AppStorage("dailyProteinGoal") private var proteinGoal: Int = 150
    @AppStorage("dailyCarbsGoal") private var carbsGoal: Int = 200
    @AppStorage("dailyFatGoal") private var fatGoal: Int = 65

    @State private var apiKeyInput: String = ""
    @State private var keySaved = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var imageApiKeyInput: String = ""
    @State private var imageKeySaved = false
    @State private var imageTestResult: String?
    @State private var isTestingImage = false
    @State private var isRecalculating = false

    private var provider: AIProvider {
        AIProvider(rawValue: providerRaw) ?? .openai
    }

    /// Proveedor de imágenes efectivo: el explícito o, si no se eligió, el de chat.
    private var imageProvider: AIProvider {
        AIProvider(rawValue: imageProviderRaw) ?? provider
    }

    private var hasSeparateImageProvider: Bool {
        AIProvider(rawValue: imageProviderRaw) != nil
    }

    private var modelBinding: Binding<String> {
        switch provider {
        case .openai: return $openaiModel
        case .claude: return $claudeModel
        case .kimi: return $kimiModel
        case .nvidia: return $nvidiaModel
        case .gemini: return $geminiModel
        }
    }

    private var visionModelBinding: Binding<String> {
        switch imageProvider {
        case .openai: return $openaiVisionModel
        case .claude: return $claudeVisionModel
        case .kimi: return $kimiVisionModel
        case .nvidia: return $nvidiaVisionModel
        case .gemini: return $geminiVisionModel
        }
    }

    private func testEndpoint(for p: AIProvider, key: String) -> (url: URL, headers: [(String, String)]) {
        switch p {
        case .openai:
            return (URL(string: "https://api.openai.com/v1/models")!,
                    [("Authorization", "Bearer \(key)")])
        case .claude:
            return (URL(string: "https://api.anthropic.com/v1/models")!,
                    [("x-api-key", key), ("anthropic-version", "2023-06-01")])
        case .kimi:
            return (URL(string: "https://api.moonshot.ai/v1/models")!,
                    [("Authorization", "Bearer \(key)")])
        case .nvidia:
            return (URL(string: "https://integrate.api.nvidia.com/v1/models")!,
                    [("Authorization", "Bearer \(key)")])
        case .gemini:
            return (URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                    [("x-goog-api-key", key)])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Proveedor", selection: $providerRaw) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    .onChange(of: providerRaw) { _, _ in
                        loadKey()
                        testResult = nil
                    }
                } header: {
                    Text("Chat (asistente y recetas)")
                }

                Section {
                    SecureField("API key", text: $apiKeyInput)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { saveKey() }
                    Button(keySaved ? "API key guardada ✓" : "Guardar API key") {
                        saveKey()
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !apiKeyInput.isEmpty {
                        Button("Eliminar API key", role: .destructive) {
                            KeychainHelper.delete(account: provider.keychainAccount)
                            apiKeyInput = ""
                            keySaved = false
                            testResult = nil
                        }
                    }
                    testButton(result: testResult, isTesting: isTesting) {
                        await testConnection(for: provider, key: apiKeyInput) { result in
                            testResult = result
                        }
                    }
                } header: {
                    Text("API key (\(provider.displayName))")
                } footer: {
                    Text("La API key se guarda de forma segura en el Keychain del dispositivo.")
                }

                Section {
                    TextField("Modelo", text: modelBinding)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Restablecer por defecto (\(provider.defaultModel))") {
                        modelBinding.wrappedValue = ""
                    }
                    .font(.footnote)
                } header: {
                    Text("Modelo (chat)")
                } footer: {
                    Text("Si lo dejas vacío se usará \(provider.defaultModel).")
                }

                Section {
                    Picker("Proveedor", selection: $imageProviderRaw) {
                        Text("Mismo que el chat").tag("")
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p.rawValue)
                        }
                    }
                    .onChange(of: imageProviderRaw) { _, _ in
                        loadImageKey()
                        imageTestResult = nil
                    }
                } header: {
                    Text("Imágenes (fotos de comida)")
                } footer: {
                    if !hasSeparateImageProvider {
                        Text("Las fotos se analizan con \(provider.displayName), igual que el chat.")
                    }
                }

                if hasSeparateImageProvider {
                    Section {
                        SecureField("API key", text: $imageApiKeyInput)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { saveImageKey() }
                        Button(imageKeySaved ? "API key guardada ✓" : "Guardar API key") {
                            saveImageKey()
                        }
                        .disabled(imageApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !imageApiKeyInput.isEmpty {
                            Button("Eliminar API key", role: .destructive) {
                                KeychainHelper.delete(account: imageProvider.keychainAccount)
                                imageApiKeyInput = ""
                                imageKeySaved = false
                                imageTestResult = nil
                            }
                        }
                        testButton(result: imageTestResult, isTesting: isTestingImage) {
                            await testConnection(for: imageProvider, key: imageApiKeyInput) { result in
                                imageTestResult = result
                            }
                        }
                    } header: {
                        Text("API key de imágenes (\(imageProvider.displayName))")
                    }
                }

                Section {
                    TextField("Modelo de visión", text: visionModelBinding)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Restablecer por defecto (\(imageProvider.defaultVisionModel))") {
                        visionModelBinding.wrappedValue = ""
                    }
                    .font(.footnote)
                } header: {
                    Text("Modelo de visión (fotos)")
                } footer: {
                    Text("Se usa para analizar las fotos de tus comidas. Si lo dejas vacío se usará \(imageProvider.defaultVisionModel).")
                }

                Section {
                    goalRow(label: "Calorías", value: $calorieGoal, unit: "kcal", range: 1000...5000, step: 50)
                    goalRow(label: "Proteína", value: $proteinGoal, unit: "g", range: 30...400, step: 5)
                    goalRow(label: "Carbohidratos", value: $carbsGoal, unit: "g", range: 30...600, step: 5)
                    goalRow(label: "Grasa", value: $fatGoal, unit: "g", range: 20...300, step: 5)
                    Button {
                        Task { await recalculateFromHealth() }
                    } label: {
                        if isRecalculating {
                            HStack { ProgressView(); Text("Calculando…").padding(.leading, 6) }
                        } else {
                            Label("Recalcular desde Apple Salud", systemImage: "heart.text.square")
                        }
                    }
                    .disabled(isRecalculating)
                } header: {
                    Text("Objetivos diarios")
                } footer: {
                    Text("Las calorías se calculan automáticamente desde tu metabolismo basal en Apple Salud. Puedes ajustarlos manualmente.")
                }
            }
            .navigationTitle("Ajustes")
            .onAppear {
                loadKey()
                loadImageKey()
            }
        }
    }

    @ViewBuilder
    private func testButton(result: String?, isTesting: Bool,
                            action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                if isTesting {
                    ProgressView().padding(.trailing, 4)
                    Text("Probando…")
                } else {
                    Label("Probar conexión", systemImage: "network")
                }
            }
        }
        .disabled(isTesting)
        if let result {
            Text(result)
                .font(.caption)
                .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
        }
    }

    private func testConnection(for p: AIProvider, key: String,
                                setResult: @escaping (String) -> Void) async {
        if p == provider { isTesting = true } else { isTestingImage = true }
        defer { if p == provider { isTesting = false } else { isTestingImage = false } }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setResult("❌ Introduce primero la API key.")
            return
        }

        let (url, headers) = testEndpoint(for: p, key: trimmed)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            if (200..<300).contains(status) {
                setResult("✅ Conexión OK (HTTP \(status))")
            } else {
                setResult("❌ HTTP \(status): \(body.prefix(200))")
            }
        } catch {
            setResult("❌ Error de red: \(error.localizedDescription)")
        }
    }

    private func goalRow(label: String, value: Binding<Int>, unit: String, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func recalculateFromHealth() async {
        isRecalculating = true
        defer { isRecalculating = false }
        let healthKit = HealthKitService()
        guard HealthKitService.isAvailable else { return }
        try? await healthKit.requestAuthorization()
        let goal = await healthKit.fetchDailyCalorieGoal()
        calorieGoal = goal
        // Derive default macros from goal (40% carbs / 30% protein / 30% fat)
        proteinGoal = Int(Double(goal) * 0.30 / 4)
        carbsGoal   = Int(Double(goal) * 0.40 / 4)
        fatGoal     = Int(Double(goal) * 0.30 / 9)
    }

    private func loadKey() {
        let stored = KeychainHelper.read(account: provider.keychainAccount) ?? ""
        apiKeyInput = stored
        keySaved = !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.save(trimmed, account: provider.keychainAccount)
        apiKeyInput = trimmed
        keySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            selectedTab = 2
        }
    }

    private func loadImageKey() {
        let stored = KeychainHelper.read(account: imageProvider.keychainAccount) ?? ""
        imageApiKeyInput = stored
        imageKeySaved = !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveImageKey() {
        let trimmed = imageApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.save(trimmed, account: imageProvider.keychainAccount)
        imageApiKeyInput = trimmed
        imageKeySaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            selectedTab = 2
        }
    }
}
