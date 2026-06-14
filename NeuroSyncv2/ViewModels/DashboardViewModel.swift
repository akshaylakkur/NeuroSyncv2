import Foundation
import SwiftUI
import Combine
import EventKit

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentMetrics: HealthMetrics?
    @Published var latestResult: StressResult?
    @Published var stressEvents: [StressEvent] = []
    @Published var isLoading = false
    @Published var isAnalyzing = false
    @Published var isMonitoring = false
    @Published var errorMessage: String?
    @Published var nvidiaApiKey: String = ""
    @Published var healthAuthorized = false
    @Published var remindersAuthorized = false
    @Published var lastUpdated: Date?

    // MARK: - Exercise State

    @Published var generatedExercisePlan: StressExercisePlan?
    @Published var showExerciseSheet = false
    @Published var autoLaunchExercise = true

    // MARK: - Services

    private let healthKitService = HealthKitService.shared
    private let nimService = NIMService.shared
    private let eventKitService = EventKitService.shared

    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        loadAPIKey()
        loadEvents()
        loadAutoLaunchSetting()
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Authorization

    func requestInitialAuthorization() {
        Task {
            do {
                // HealthKit
                if healthKitService.isHealthDataAvailable {
                    healthAuthorized = try await healthKitService.requestAuthorization()
                    if healthAuthorized {
                        healthKitService.startObservingChanges { [weak self] in
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                await self?.refreshMetrics()
                            }
                        }
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            // EventKit
            do {
                _ = try await eventKitService.requestRemindersAccess()
                remindersAuthorized = eventKitService.isAuthorized
            } catch {
                // Not critical — reminders will fail gracefully later
                remindersAuthorized = false
            }
        }
    }

    // MARK: - Data Refresh

    func refreshMetrics() async {
        guard healthAuthorized else {
            // HealthKit not yet authorized — try again later
            return
        }

        isLoading = true
        errorMessage = nil

        let metrics = await healthKitService.fetchLatestMetrics()
        currentMetrics = metrics
        lastUpdated = Date()

        // Auto-analyze if we have at least 3 metrics
        if metrics.nonNilCount >= 3 && !nvidiaApiKey.isEmpty {
            await runStressAnalysis(metrics: metrics)
        }

        isLoading = false
    }

    func runStressAnalysis() async {
        guard let metrics = currentMetrics else {
            errorMessage = "No health data to analyze. Pull down to refresh first."
            return
        }
        guard !nvidiaApiKey.isEmpty else {
            errorMessage = "Please set your NVIDIA API key in Settings."
            return
        }
        await runStressAnalysis(metrics: metrics)
    }

    private func runStressAnalysis(metrics: HealthMetrics) async {
        guard !nvidiaApiKey.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil

        do {
            let result = try await nimService.analyzeStress(metrics: metrics, apiKey: nvidiaApiKey)
            latestResult = result

            // Save event
            var event = StressEvent(metrics: metrics, result: result)
            // If stress is high or critical, create a reminder
            if result.stressLevel == .high || result.stressLevel == .critical {
                do {
                    event.reminderCreated = try await eventKitService.createStressReminder(suggestion: result.suggestion)
                } catch {
                    event.reminderCreated = false
                }

                // Generate a personalized breathing exercise
                do {
                    let plan = try await nimService.generateExercise(
                        metrics: metrics,
                        stressResult: result,
                        apiKey: nvidiaApiKey
                    )
                    generatedExercisePlan = plan
                } catch {
                    // Use the fallback plan if LLM exercise generation fails
                    generatedExercisePlan = StressExerciseManager.fallbackPlan
                }

                // Auto-launch the exercise sheet if enabled
                if autoLaunchExercise {
                    showExerciseSheet = true
                }
            } else {
                // Reset exercise state when stress is not high/critical
                generatedExercisePlan = nil
                showExerciseSheet = false
            }
            stressEvents.insert(event, at: 0)
            saveEvents()

            lastUpdated = Date()
        } catch {
            errorMessage = "Stress analysis failed: \(error.localizedDescription)"
        }

        isAnalyzing = false
    }

    // MARK: - Auto-Refresh Loop

    func startAutoRefresh() {
        isMonitoring = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self = self else { return }
            // Wait for HealthKit authorization before fetching
            var waited = 0
            while !self.healthAuthorized && waited < 15 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                waited += 1
            }

            // Initial fetch
            await self.refreshMetrics()

            // Periodic refresh every 5 minutes
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConfig.healthFetchInterval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self.refreshMetrics()
            }
        }
    }

    func stopAutoRefresh() {
        isMonitoring = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Human-readable monitoring status string.
    var monitoringStatus: String {
        guard healthAuthorized else { return "Waiting for Health access…" }
        guard isMonitoring else { return "Monitoring paused" }
        if let last = lastUpdated {
            let ago = Int(-last.timeIntervalSinceNow)
            if ago < 60 { return "Updated \(ago)s ago" }
            return "Updated \(ago / 60)m ago"
        }
        return "Monitoring…"
    }

    // MARK: - Persistence

    private func loadEvents() {
        stressEvents = BackgroundTaskService.loadEvents()
    }

    private func saveEvents() {
        BackgroundTaskService.saveEvents(stressEvents)
    }

    /// Clears all stress event history.
    func clearHistory() {
        stressEvents.removeAll()
        BackgroundTaskService.saveEvents(stressEvents)
    }

    // MARK: - API Key Management

    func saveAPIKey(_ key: String) {
        nvidiaApiKey = key
        KeychainHelper.save(key: AppConfig.apiKeyAccount, value: key)
    }

    private func loadAPIKey() {
        if let key = KeychainHelper.load(key: AppConfig.apiKeyAccount) {
            nvidiaApiKey = key
        }
    }

    // MARK: - Auto-Launch Exercise

    /// Enable or disable auto-launching the breathing exercise sheet when high/critical stress is detected.
    func setAutoLaunchExercise(_ enabled: Bool) {
        autoLaunchExercise = enabled
        UserDefaults.standard.set(enabled, forKey: AppConfig.autoLaunchExerciseKey)
    }

    private func loadAutoLaunchSetting() {
        // Register default so the first launch defaults to true
        if UserDefaults.standard.object(forKey: AppConfig.autoLaunchExerciseKey) == nil {
            UserDefaults.standard.set(true, forKey: AppConfig.autoLaunchExerciseKey)
        }
        autoLaunchExercise = UserDefaults.standard.bool(forKey: AppConfig.autoLaunchExerciseKey)
    }
}