import Foundation
import Combine
import BackgroundTasks
import EventKit

@MainActor
final class SettingsViewModel: ObservableObject {

    @Published var apiKey: String = ""
    @Published var backgroundRefreshEnabled = true
    @Published var healthPermissionStatus: String = "Unknown"
    @Published var remindersPermissionStatus: String = "Unknown"
    @Published var showSavedAlert = false
    @Published var showClearConfirmation = false

    private let healthKitService = HealthKitService.shared
    private let eventKitService = EventKitService.shared

    init() {
        loadSettings()
    }

    func loadSettings() {
        // API Key
        apiKey = KeychainHelper.load(key: AppConfig.apiKeyAccount) ?? ""

        // Background refresh
        backgroundRefreshEnabled = UserDefaults.standard.bool(forKey: AppConfig.bgRefreshEnabledKey)

        // HealthKit status
        healthPermissionStatus = healthKitService.isHealthDataAvailable
            ? "Available"
            : "Not Available"

        // EventKit status
        switch eventKitService.authorizationStatus {
        case .authorized, .fullAccess, .writeOnly:
            remindersPermissionStatus = "Authorized"
        case .denied:
            remindersPermissionStatus = "Denied"
        case .restricted:
            remindersPermissionStatus = "Restricted"
        case .notDetermined:
            remindersPermissionStatus = "Not Requested"
        @unknown default:
            remindersPermissionStatus = "Unknown"
        }
    }

    func saveAPIKey(_ key: String) {
        guard !key.isEmpty else { return }
        KeychainHelper.save(key: AppConfig.apiKeyAccount, value: key)
        apiKey = key
        showSavedAlert = true
    }

    func toggleBackgroundRefresh(_ enabled: Bool) {
        backgroundRefreshEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: AppConfig.bgRefreshEnabledKey)

        if enabled {
            BackgroundTaskService.shared.scheduleBackgroundCheck()
        } else {
            BackgroundTaskService.shared.cancelAllPendingTasks()
        }
    }

    func clearHistory(completion: @escaping () -> Void) {
        BackgroundTaskService.saveEvents([])
        completion()
    }
}