import Foundation

enum StressLevel: String, Codable, CaseIterable {
    case low
    case moderate
    case high
    case critical
}

struct StressResult: Codable {
    let stressLevel: StressLevel
    let confidence: Double
    let reasoning: String
    let suggestion: String
}