import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    case invalidResponse
    case httpError(status: Int, body: String)
    case unmatchedExercises([String])

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "El backend no está configurado. Revisa Ajustes > Speediance."
        case .invalidResponse:
            return "La respuesta del backend no es válida."
        case .httpError(let status, let body):
            return "Error HTTP \(status) del backend: \(body.prefix(300))"
        case .unmatchedExercises(let names):
            return "No reconozco estos ejercicios: \(names.joined(separator: ", ")). Díselo al coach para corregir la rutina."
        }
    }
}

struct BackendExerciseDTO: Decodable, Sendable {
    let name: String
    let sets: Int
    let reps: Int
    let weightKg: Double?
}

struct BackendWorkoutDTO: Decodable, Sendable {
    let id: String
    let title: String
    let date: Date
    let durationMinutes: Int
    let calories: Int
    let exercises: [BackendExerciseDTO]
}

struct BackendWorkoutsResponse: Decodable, Sendable {
    let workouts: [BackendWorkoutDTO]
}

struct UploadTemplateResponse: Decodable, Sendable {
    let code: String
    let name: String
    let movementCount: Int
    let deduplicated: Bool
}

private struct BackendHealthResponse: Decodable {
    let status: String
    let speediance: String
}

protocol BackendServing: Sendable {
    /// Devuelve las sesiones desde `since` (nil = todo el historial).
    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO]
    /// true si el backend responde y además tiene login válido en Speediance.
    func checkHealth() async throws -> Bool
    /// Sube una rutina como plantilla a Speediance. Idempotente por nombre.
    func uploadTemplate(_ routine: RoutineProposal) async throws -> UploadTemplateResponse
}

struct BackendService: BackendServing {
    static let urlDefaultsKey = "backendBaseURL"
    static let apiKeyAccount = "myfit.backend.apikey"
    /// @AppStorage muestra este valor pero NO lo persiste hasta que el usuario edita el
    /// campo, así que fromStoredConfiguration también debe usarlo como fallback.
    static let defaultBaseURL = "http://100.77.65.26:8000"

    let baseURL: URL
    let apiKey: String

    static func fromStoredConfiguration() -> BackendService? {
        let raw = UserDefaults.standard.string(forKey: urlDefaultsKey) ?? defaultBaseURL
        guard let url = URL(string: raw),
              let key = KeychainHelper.read(account: apiKeyAccount),
              !key.isEmpty else { return nil }
        return BackendService(baseURL: url, apiKey: key)
    }

    /// Acepta ISO8601 con y sin fracción de segundo.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractional.date(from: string) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Fecha ISO8601 inválida: \(string)")
        }
        return decoder
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw BackendError.notConfigured }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw BackendError.notConfigured }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        return request
    }

    func fetchWorkouts(since: Date?) async throws -> [BackendWorkoutDTO] {
        var queryItems: [URLQueryItem] = []
        if let since {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            queryItems = [URLQueryItem(name: "since", value: formatter.string(from: since))]
        }
        var request = try makeRequest(path: "speediance/workouts", queryItems: queryItems)
        // La primera importación recorre todo el historial a 1 petición/s: puede tardar minutos.
        request.timeoutInterval = 600
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpError(status: http.statusCode,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.makeDecoder().decode(BackendWorkoutsResponse.self, from: data).workouts
    }

    /// Extrae los nombres no resueltos de un 422 del backend. Internal para tests.
    static func parseUnmatched(from data: Data) -> [String]? {
        struct ErrorBody: Decodable {
            struct Detail: Decodable { let unmatched: [String] }
            let detail: Detail
        }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).detail.unmatched
    }

    func uploadTemplate(_ routine: RoutineProposal) async throws -> UploadTemplateResponse {
        var request = try makeRequest(path: "speediance/templates")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(routine)
        request.timeoutInterval = 120
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        if http.statusCode == 422, let names = Self.parseUnmatched(from: data) {
            throw BackendError.unmatchedExercises(names)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpError(status: http.statusCode,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(UploadTemplateResponse.self, from: data)
    }

    func checkHealth() async throws -> Bool {
        let request = try makeRequest(path: "health")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.httpError(status: http.statusCode,
                                         body: String(data: data, encoding: .utf8) ?? "")
        }
        let health = try JSONDecoder().decode(BackendHealthResponse.self, from: data)
        return health.speediance == "connected"
    }
}
