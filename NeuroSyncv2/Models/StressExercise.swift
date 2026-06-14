import Foundation

// MARK: - Phase Type

enum StressExercisePhaseType: String, Codable, CaseIterable {
    case inhale
    case hold
    case exhale
    case rest
}

// MARK: - Phase

struct StressExercisePhase: Codable {
    let type: StressExercisePhaseType
    let durationSeconds: Int
    let instruction: String
    let voicePrompt: String
}

// MARK: - Exercise Plan

struct StressExercisePlan: Codable {
    let name: String
    let phases: [StressExercisePhase]
    /// A short, natural-language spoken summary for Siri to read aloud.
    /// Example: "Your heart rate is elevated at 92 and your HRV is quite low.
    /// I've designed a 3-minute exercise called 'Ocean Breaths' for you."
    let spokenSummary: String

    var totalDurationSeconds: Int {
        phases.reduce(0) { $0 + $1.durationSeconds }
    }
}