import Foundation
import BackgroundTasks

/// Service for scheduling and handling background stress checks.
final class BackgroundTaskService {

    static let shared = BackgroundTaskService()

    private let healthKitService = HealthKitService.shared
    private let nimService = NIMService.shared
    private let eventKitService = EventKitService.shared

    // MARK: - Registration

    /// Call once at app launch to register the background task.
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppConfig.bgTaskIdentifier, using: nil) { task in
            self.handleStressCheck(task: task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next background stress check.
    func scheduleBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConfig.bgTaskMinimumInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Background task scheduling failed: \(error.localizedDescription)")
        }
    }

    /// Cancel all pending background tasks.
    func cancelAllPendingTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppConfig.bgTaskIdentifier)
    }

    // MARK: - Task Handler

    private func handleStressCheck(task: BGAppRefreshTask) {
        // Reschedule the next check
        scheduleBackgroundCheck()

        // Ensure setTaskCompleted is called exactly once, even if expiration fires.
        let completionLock = NSLock()
        var didComplete = false

        func markCompleted(success: Bool) {
            completionLock.lock()
            defer { completionLock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            markCompleted(success: false)
        }

        // Run on MainActor since we interact with MainActor-isolated services
        Task { @MainActor in
            guard !Task.isCancelled else {
                markCompleted(success: false)
                return
            }

            do {
                let metrics = await healthKitService.fetchLatestMetrics()

                let apiKey = KeychainHelper.load(key: AppConfig.apiKeyAccount)
                guard let key = apiKey, !key.isEmpty else {
                    markCompleted(success: true)
                    return
                }

                let result = try await nimService.analyzeStress(metrics: metrics, apiKey: key)

                var event = StressEvent(metrics: metrics, result: result)

                if result.stressLevel == .high || result.stressLevel == .critical {
                    do {
                        let created = try await eventKitService.createStressReminder(suggestion: result.suggestion)
                        event.reminderCreated = created
                    } catch {
                        event.reminderCreated = false
                    }

                    // Generate an exercise plan and persist it for the next app open
                    do {
                        let plan = try await nimService.generateExercise(
                            metrics: metrics,
                            stressResult: result,
                            apiKey: key
                        )
                        if let data = try? JSONEncoder().encode(plan) {
                            UserDefaults.standard.set(data, forKey: AppConfig.lastExercisePlanKey)
                        }
                    } catch {
                        // Silently skip — user still gets the reminder
                        print("Background exercise generation failed: \(error.localizedDescription)")
                    }
                }

                var events = Self.loadEvents()
                events.insert(event, at: 0)
                Self.saveEvents(events)
                markCompleted(success: true)
            } catch {
                markCompleted(success: false)
            }
        }
    }

    // MARK: - Persistence Helpers

    static func loadEvents() -> [StressEvent] {
        guard let data = UserDefaults.standard.data(forKey: AppConfig.stressEventsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        return (try? decoder.decode([StressEvent].self, from: data)) ?? []
    }

    static func saveEvents(_ events: [StressEvent]) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(events) else { return }
        UserDefaults.standard.set(data, forKey: AppConfig.stressEventsKey)
    }
}