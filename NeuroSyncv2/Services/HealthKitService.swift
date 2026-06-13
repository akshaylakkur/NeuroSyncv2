import Foundation
import HealthKit

/// Service for reading health metrics from HealthKit.
final class HealthKitService {

    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    private let isoFormatter = ISO8601DateFormatter()

    // MARK: - HealthKit Types

    private var allReadTypes: Set<HKObjectType> {
        Set([
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .mindfulSession)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
        ])
    }

    // MARK: - Authorization

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws -> Bool {
        guard isHealthDataAvailable else {
            throw HealthKitError.notAvailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: allReadTypes) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    // MARK: - Fetch Metrics

    func fetchLatestMetrics() async -> HealthMetrics {
        async let hr = try? latestHeartRate()
        async let hrv = try? latestHRV()
        async let sleep = try? lastNightSleepHours()
        async let steps = try? todaySteps()
        async let exercise = try? todayExerciseMinutes()
        async let mindful = try? todayMindfulMinutes()
        async let respRate = try? latestRespiratoryRate()

        return await HealthMetrics(
            heartRate: hr,
            hrv: hrv,
            sleepHours: sleep,
            steps: steps,
            exerciseMinutes: exercise,
            mindfulMinutes: mindful,
            respiratoryRate: respRate,
            timestamp: Date()
        )
    }

    // MARK: - Observer Query

    func startObservingChanges(handler: @escaping () -> Void) {
        for type in allReadTypes {
            guard let sampleType = type as? HKSampleType else { continue }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, _, _ in
                handler()
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Private Helpers

    private func latestHeartRate() async -> Double? {
        await latestQuantitySample(for: .heartRate, unit: .count().unitDivided(by: .minute()))
    }

    private func latestHRV() async -> Double? {
        await latestQuantitySample(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
    }

    private func latestRespiratoryRate() async -> Double? {
        await latestQuantitySample(for: .respiratoryRate, unit: .count().unitDivided(by: .minute()))
    }

    private func lastNightSleepHours() async -> Double? {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                // Find the most recent sleep session (samples sorted newest first)
                let sleepSamples = samples.filter {
                    $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue
                }
                guard !sleepSamples.isEmpty else {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                // Walk backwards from the newest sample, grouping those within 3h
                let newestEnd = sleepSamples[0].endDate
                var sessionStart = sleepSamples[0].startDate
                for sample in sleepSamples {
                    if newestEnd.timeIntervalSince(sample.endDate) < 3 * 3600 {
                        sessionStart = min(sessionStart, sample.startDate)
                    } else { break }
                }
                let hours = newestEnd.timeIntervalSince(sessionStart) / 3600.0
                continuation.resume(returning: hours > 0 ? min(hours, 16) : nil)
            }
            healthStore.execute(query)
        }
    }

    private func todaySteps() async -> Int? {
        await todayCumulativeSum(for: .stepCount, unit: .count())
    }

    private func todayExerciseMinutes() async -> Double? {
        await todayCumulativeDoubleSum(for: .appleExerciseTime, unit: .minute())
    }

    private func todayMindfulMinutes() async -> Double? {
        let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: mindfulType, predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                let totalMinutes = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60.0
                continuation.resume(returning: totalMinutes > 0 ? totalMinutes : nil)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Generic Queries

    private func latestQuantitySample(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -30, to: Date()), end: Date())
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func todayCumulativeDoubleSum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if error != nil {
                    continuation.resume(returning: nil as Double?)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func todayCumulativeSum(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Int? {
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if error != nil {
                    continuation.resume(returning: nil as Int?)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value.map(Int.init))
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case noData

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Health data is not available on this device."
        case .noData: return "No health data found."
        }
    }
}