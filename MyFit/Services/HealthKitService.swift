import Foundation
import HealthKit

final class HealthKitService: @unchecked Sendable {
    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        let types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.bodyMassIndex),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.height),
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        ]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: types) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func fetchBodyComposition(from startDate: Date? = nil) async throws -> [Date: (fatPct: Double?, muscleKg: Double?, bmi: Double?)] {
        let fat    = try await fetchQuantity(.bodyFatPercentage, from: startDate)
        let muscle = try await fetchQuantity(.leanBodyMass, from: startDate)
        let bmi    = try await fetchQuantity(.bodyMassIndex, from: startDate)

        var result: [Date: (fatPct: Double?, muscleKg: Double?, bmi: Double?)] = [:]
        for s in fat {
            let day = Calendar.current.startOfDay(for: s.startDate)
            result[day] = (s.quantity.doubleValue(for: .percent()), result[day]?.muscleKg, result[day]?.bmi)
        }
        for s in muscle {
            let day = Calendar.current.startOfDay(for: s.startDate)
            let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
            result[day] = (result[day]?.fatPct, kg, result[day]?.bmi)
        }
        for s in bmi {
            let day = Calendar.current.startOfDay(for: s.startDate)
            let val = s.quantity.doubleValue(for: .count())
            result[day] = (result[day]?.fatPct, result[day]?.muscleKg, val)
        }
        return result
    }

    func fetchDailyCalorieGoal() async -> Int {
        // 1. Try average basalEnergyBurned from last 7 days (Apple Watch)
        if let basal = await fetchRecentDailyAverage(.basalEnergyBurned, unit: .kilocalorie(), days: 7),
           basal > 500 {
            let active = await fetchRecentDailyAverage(.activeEnergyBurned, unit: .kilocalorie(), days: 7) ?? 300
            return Int(basal + active)
        }
        // 2. Mifflin-St Jeor from biometrics
        guard let weightKg = await fetchLatestQuantity(.bodyMass, unit: .gramUnit(with: .kilo)),
              let heightCm = await fetchLatestQuantity(.height, unit: .meterUnit(with: .centi)) else {
            return 2000
        }
        let age: Double
        if let dob = try? store.dateOfBirthComponents().date {
            age = Double(Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 30)
        } else {
            age = 30
        }
        let sex = (try? store.biologicalSex().biologicalSex) ?? .notSet
        let bmr: Double
        if sex == .female {
            bmr = 10 * weightKg + 6.25 * heightCm - 5 * age - 161
        } else {
            bmr = 10 * weightKg + 6.25 * heightCm - 5 * age + 5
        }
        return max(1200, Int(bmr * 1.375))
    }

    private func fetchRecentDailyAverage(_ type: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        guard let samples = try? await fetchQuantity(type, from: start), !samples.isEmpty else { return nil }
        let total = samples.map { $0.quantity.doubleValue(for: unit) }.reduce(0, +)
        return total / Double(days)
    }

    private func fetchLatestQuantity(_ type: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let samples = try? await fetchQuantity(type, from: nil), let last = samples.first else { return nil }
        return last.quantity.doubleValue(for: unit)
    }

    private func fetchQuantity(_ type: HKQuantityTypeIdentifier, from startDate: Date?) async throws -> [HKQuantitySample] {
        let predicate = startDate.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(type),
                predicate: predicate,
                limit: 500,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples as? [HKQuantitySample]) ?? []) }
            }
            self.store.execute(query)
        }
    }

    func fetchWeightSamples(from startDate: Date? = nil, limit: Int = 500) async throws -> [(date: Date, kg: Double)] {
        let type = HKQuantityType(.bodyMass)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let predicate = startDate.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let results = (samples as? [HKQuantitySample] ?? []).map { sample in
                    (date: sample.startDate, kg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
                }
                continuation.resume(returning: results)
            }
            self.store.execute(query)
        }
    }

    func fetchWorkouts(from startDate: Date? = nil, limit: Int = 500) async throws -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let predicate = startDate.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
                }
            }
            store.execute(query)
        }
    }

    func toWorkout(_ hk: HKWorkout) -> Workout {
        let kcal = hk.totalEnergyBurned.map { Int($0.doubleValue(for: .kilocalorie())) }
        return Workout(
            date: hk.startDate,
            type: workoutType(for: hk.workoutActivityType),
            durationMinutes: max(1, Int(hk.duration / 60)),
            notes: "Importado de \(hk.sourceRevision.source.name)",
            caloriesBurned: kcal
        )
    }

    private func workoutType(for activityType: HKWorkoutActivityType) -> WorkoutType {
        switch activityType {
        case .cycling:
            return .cardio
        case .running, .walking, .hiking, .swimming, .rowing,
             .elliptical, .stairClimbing, .highIntensityIntervalTraining:
            return .cardio
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining:
            return .strength
        case .yoga, .pilates, .flexibility, .mindAndBody:
            return .mobility
        case .soccer, .basketball, .tennis, .volleyball, .badminton, .baseball, .golf:
            return .sport
        default:
            return .other
        }
    }
}
