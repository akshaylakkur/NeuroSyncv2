import Foundation

struct StressEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let metrics: HealthMetrics
    let result: StressResult
    var reminderCreated: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        metrics: HealthMetrics,
        result: StressResult,
        reminderCreated: Bool = false
    ) {
        self.id = id
        self.date = date
        self.metrics = metrics
        self.result = result
        self.reminderCreated = reminderCreated
    }

    static func == (lhs: StressEvent, rhs: StressEvent) -> Bool {
        lhs.id == rhs.id
    }
}