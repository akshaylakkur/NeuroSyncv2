import AppIntents
import Foundation

/// Shared App Group identifier — must match the Xcode capability.
private let appGroupID = "group.com.akshaylakkur.NeuroSyncv2App"
private let planKey = "com.neurosync.pending_plan"

/// Helper: reads from the shared App Group store.
func readSharedPlan() -> StressExercisePlan? {
    let store = UserDefaults(suiteName: appGroupID)
    guard let data = store?.data(forKey: planKey) else { return nil }
    store?.removeObject(forKey: planKey)
    return try? JSONDecoder().decode(StressExercisePlan.self, from: data)
}

/// Helper: writes to the shared App Group store.
func writeSharedPlan(_ plan: StressExercisePlan) {
    guard let data = try? JSONEncoder().encode(plan) else { return }
    let store = UserDefaults(suiteName: appGroupID)
    store?.set(data, forKey: planKey)
}

/// Siri intent that creates a demo box-breathing exercise plan and stores
/// it in the shared App Group UserDefaults, visible to the app process.
@available(iOS 17.0, *)
struct StressExerciseIntent: AppIntent {

    static var title: LocalizedStringResource = "Start NeuroSync Stress Exercise"
    static var description: IntentDescription = "Starts a guided breathing exercise on NeuroSync."

    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let plan = StressExercisePlan(
            name: "Box Breathing",
            phases: [
                StressExercisePhase(type: .inhale, durationSeconds: 4, instruction: "Breathe in slowly through your nose", voicePrompt: "Breathe in..."),
                StressExercisePhase(type: .hold, durationSeconds: 4, instruction: "Hold gently", voicePrompt: "Hold..."),
                StressExercisePhase(type: .exhale, durationSeconds: 4, instruction: "Breathe out slowly through your mouth", voicePrompt: "Breathe out..."),
                StressExercisePhase(type: .rest, durationSeconds: 4, instruction: "Rest and relax", voicePrompt: "Rest..."),
                StressExercisePhase(type: .inhale, durationSeconds: 4, instruction: "Breathe in slowly through your nose", voicePrompt: "Breathe in..."),
                StressExercisePhase(type: .hold, durationSeconds: 4, instruction: "Hold gently", voicePrompt: "Hold..."),
                StressExercisePhase(type: .exhale, durationSeconds: 4, instruction: "Breathe out slowly through your mouth", voicePrompt: "Breathe out..."),
                StressExercisePhase(type: .rest, durationSeconds: 4, instruction: "Rest and relax", voicePrompt: "Rest..."),
            ],
            spokenSummary: ""
        )

        writeSharedPlan(plan)
        return .result(dialog: "Opening NeuroSync for your breathing exercise.")
    }
}