import Foundation
import Combine
import EventKit

/// ViewModel for the social sentiment tab in the iOS app.
/// Polls the NeuroSync server every 30s for social sentiment data,
/// creates iOS Reminders when social stress is high.
@MainActor
final class SocialSentimentViewModel: ObservableObject {

    // MARK: - Published State

    @Published var dashboard: SocialDashboard?
    @Published var urgentAlert: UrgentAlertResponse?
    @Published var messages: [SocialMessage] = []
    @Published var isLoading = false
    @Published var isPolling = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    @Published var showUrgentAlert = false

    // MARK: - Services

    private let socialService = SocialSentimentService.shared
    private let eventKitService = EventKitService.shared
    private var pollTask: Task<Void, Never>?
    private var reminderCheckTask: Task<Void, Never>?

    // MARK: - Public API

    /// Start the auto-polling loop (30s interval).
    func startPolling() {
        isPolling = true
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self = self else { return }
            // Initial fetch
            await self.refresh()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.socialPollInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }

        // Separate task to check for pending reminders
        reminderCheckTask?.cancel()
        reminderCheckTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000)) // Check every 60s
                guard !Task.isCancelled else { break }
                await self.checkPendingReminders()
            }
        }
    }

    /// Stop auto-polling.
    func stopPolling() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
        reminderCheckTask?.cancel()
        reminderCheckTask = nil
    }

    /// Manual one-shot refresh.
    func refresh() async {
        isLoading = true
        errorMessage = nil

        await socialService.fetchDashboard()
        dashboard = socialService.dashboard

        if let error = socialService.errorMessage {
            errorMessage = error
        }

        // Also fetch urgent alerts
        urgentAlert = await socialService.fetchUrgentAlerts()
        if let alert = urgentAlert, alert.crisisActive {
            showUrgentAlert = true
        }

        // Refresh messages
        if dashboard != nil {
            messages = dashboard?.recentMessages ?? []
        }

        lastUpdated = socialService.lastFetched ?? Date()
        isLoading = false
    }

    /// Check for pending reminders on the server and create them locally.
    func checkPendingReminders() async {
        let reminders = await socialService.fetchPendingReminders()
        for reminderData in reminders {
            await createLocalReminder(from: reminderData)
        }
    }

    /// Create a local iOS Reminder from server reminder data.
    func createLocalReminder(from data: [String: Any]) async {
        do {
            let title = data["title"] as? String ?? "🧠 NeuroSync: Social Stress Alert"
            let notes = data["notes"] as? String ?? ""
            let stressLevel = data["stress_level"] as? String ?? "unknown"

            _ = try await eventKitService.createReminder(
                title: title,
                notes: notes,
                dueMinutesFromNow: 15
            )

            // Also post health correlation if we have health data
            await socialService.postHealthStress(
                stressLevel: stressLevel,
                confidence: 0.85
            )
        } catch {
            print("Failed to create social reminder: \(error.localizedDescription)")
        }
    }

    /// When social stress is high, immediately create a reminder and post correlation.
    func handleHighSocialStress(stressLevel: String, reason: String) async {
        // Create local reminder
        let created = await socialService.requestSocialReminder(
            stressLevel: stressLevel,
            reason: reason
        )
        if created {
            // Also trigger a local EventKit reminder as backup
            await createLocalReminder(from: [
                "title": "🧠 NeuroSync: Social Stress Alert - \(stressLevel.uppercased())",
                "notes": reason,
                "stress_level": stressLevel,
            ])
        }
    }

    /// Post current health stress to server for correlation.
    func postHealthCorrelation(stressLevel: String, confidence: Double) async {
        await socialService.postHealthStress(stressLevel: stressLevel, confidence: confidence)
    }

    /// Human-readable status string.
    var statusText: String {
        guard isPolling else { return "Monitoring paused"}
        if let last = lastUpdated {
            let ago = Int(-last.timeIntervalSinceNow)
            if ago < 60 { return "Updated \(ago)s ago" }
            return "Updated \(ago / 60)m ago"
        }
        return "Monitoring…"
    }

    /// Combined stress display string.
    var combinedStressDisplay: String {
        dashboard?.combinedStressLevel.uppercased() ?? "—"
    }

    /// Whether a crisis is active.
    var crisisActive: Bool {
        dashboard?.crisisActive ?? false
    }

    /// Count of urgent messages.
    var urgentCount: Int {
        dashboard?.totalUrgent ?? 0
    }
}