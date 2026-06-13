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

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        let operation = AsyncBlockOperation { [weak self] completion in
            guard let self = self else {
                completion()
                return
            }

            Task {
                do {
                    // Fetch metrics
                    let metrics = try await self.healthKitService.fetchLatestMetrics()

                    // Load API key from Keychain
                    let apiKey = KeychainHelper.load(key: AppConfig.apiKeyAccount)

                    guard let key = apiKey, !key.isEmpty else {
                        completion()
                        return
                    }

                    // Analyze stress
                    let result = try await self.nimService.analyzeStress(metrics: metrics, apiKey: key)

                    // Save event to UserDefaults
                    var event = StressEvent(metrics: metrics, result: result)

                    // If high stress, create reminder
                    if result.stressLevel == .high {
                        do {
                            let created = try await self.eventKitService.createStressReminder(suggestion: result.suggestion)
                            event.reminderCreated = created
                        } catch {
                            event.reminderCreated = false
                        }
                    }

                    // Persist
                    var events = Self.loadEvents()
                    events.insert(event, at: 0)
                    Self.saveEvents(events)

                    task.setTaskCompleted(success: true)
                } catch {
                    task.setTaskCompleted(success: false)
                }
                completion()
            }
        }

        queue.addOperation(operation)
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

// MARK: - Async Block Operation

/// A simple Operation subclass that runs an async block with a completion callback.
private class AsyncBlockOperation: Operation {
    private let block: (@escaping () -> Void) -> Void
    private var _isExecuting = false
    private var _isFinished = false

    override var isAsynchronous: Bool { true }
    override var isExecuting: Bool { _isExecuting }
    override var isFinished: Bool { _isFinished }

    init(block: @escaping (@escaping () -> Void) -> Void) {
        self.block = block
    }

    override func start() {
        willChangeValue(forKey: "isExecuting")
        _isExecuting = true
        didChangeValue(forKey: "isExecuting")

        block { [weak self] in
            guard let self = self else { return }
            self.willChangeValue(forKey: "isExecuting")
            self.willChangeValue(forKey: "isFinished")
            self._isExecuting = false
            self._isFinished = true
            self.didChangeValue(forKey: "isExecuting")
            self.didChangeValue(forKey: "isFinished")
        }
    }
}