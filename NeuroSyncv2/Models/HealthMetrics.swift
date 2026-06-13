import Foundation

struct HealthMetrics: Codable, Identifiable {
    let id: UUID
    let heartRate: Double?
    let hrv: Double?
    let sleepHours: Double?
    let steps: Int?
    let exerciseMinutes: Double?
    let mindfulMinutes: Double?
    let respiratoryRate: Double?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        heartRate: Double? = nil,
        hrv: Double? = nil,
        sleepHours: Double? = nil,
        steps: Int? = nil,
        exerciseMinutes: Double? = nil,
        mindfulMinutes: Double? = nil,
        respiratoryRate: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.heartRate = heartRate
        self.hrv = hrv
        self.sleepHours = sleepHours
        self.steps = steps
        self.exerciseMinutes = exerciseMinutes
        self.mindfulMinutes = mindfulMinutes
        self.respiratoryRate = respiratoryRate
        self.timestamp = timestamp
    }

    /// A dictionary representation for sending to the LLM.
    var llmRepresentation: [String: Any] {
        var dict: [String: Any] = [:]
        dict["heartRate"] = heartRate as Any
        dict["hrv"] = hrv as Any
        dict["sleepHours"] = sleepHours as Any
        dict["steps"] = steps as Any
        dict["exerciseMinutes"] = exerciseMinutes as Any
        dict["mindfulMinutes"] = mindfulMinutes as Any
        dict["respiratoryRate"] = respiratoryRate as Any
        dict["timestamp"] = ISO8601DateFormatter().string(from: timestamp)
        return dict
    }

    /// Returns the number of metrics that have actual values (not nil).
    var nonNilCount: Int {
        let values: [Double?] = [heartRate, hrv, sleepHours, steps.map(Double.init), exerciseMinutes, mindfulMinutes, respiratoryRate]
        return values.compactMap { $0 }.count
    }
}