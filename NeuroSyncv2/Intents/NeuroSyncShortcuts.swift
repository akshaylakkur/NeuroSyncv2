import AppIntents
import Foundation

/// Registers Siri shortcut phrases for the NeuroSync app.
/// Siri automatically learns these phrases after the app is installed and launched once.
@available(iOS 17.0, *)
struct NeuroSyncShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StressExerciseIntent(),
            phrases: [
                "Start a NeuroSync stress exercise with \(.applicationName)",
                "Start a breathing exercise with \(.applicationName)",
                "Begin a stress relief exercise on \(.applicationName)",
                "Help me de-stress with \(.applicationName)",
                "Do a breathing exercise with \(.applicationName)",
            ],
            shortTitle: "Start Stress Exercise",
            systemImageName: "wind"
        )
    }
}