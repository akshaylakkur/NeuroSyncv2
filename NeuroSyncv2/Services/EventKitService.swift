import Foundation
import EventKit

/// Service for creating reminders in the Reminders app via EventKit.
final class EventKitService: @unchecked Sendable {

    static let shared = EventKitService()

    private let eventStore = EKEventStore()

    // MARK: - Authorization

    /// Requests write access to reminders.
    func requestRemindersAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestFullAccessToReminders()
        } else {
            return try await eventStore.requestAccess(to: .reminder)
        }
    }

    /// Checks current authorization status for reminders.
    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Returns true if the user has authorized reminders access (including iOS 17+ full/write access).
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess, .writeOnly:
            return true
        default:
            return false
        }
    }

    // MARK: - Create Reminder

    /// Creates a stress management reminder in the default reminders list.
    /// - Parameter suggestion: The LLM-generated suggestion to include as notes.
    /// - Returns: True if the reminder was created successfully.
    func createStressReminder(suggestion: String) async throws -> Bool {
        try await createReminder(
            title: "🧘 NeuroSync: Time to de-stress",
            notes: suggestion,
            dueMinutesFromNow: 15
        )
    }

    /// Generic reminder creation with custom title and notes.
    func createReminder(title: String, notes: String, dueMinutesFromNow: Int = 15) async throws -> Bool {
        try await ensureAuthorized()

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw EventKitError.noDefaultCalendar
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        reminder.isCompleted = false

        // Add notes if non-empty
        if !notes.isEmpty {
            reminder.notes = notes
        }

        let dueDate = Date().addingTimeInterval(TimeInterval(dueMinutesFromNow * 60))
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )

        let alarm = EKAlarm(absoluteDate: dueDate.addingTimeInterval(-5 * 60))
        reminder.addAlarm(alarm)

        try eventStore.save(reminder, commit: true)
        return true
    }

    // MARK: - Private

    private func ensureAuthorized() async throws {
        let status = authorizationStatus
        switch status {
        case .notDetermined:
            _ = try await requestRemindersAccess()
        case .denied, .restricted:
            throw EventKitError.accessDenied
        case .authorized, .fullAccess, .writeOnly:
            break
        @unknown default:
            throw EventKitError.accessDenied
        }
    }
}

// MARK: - Errors

enum EventKitError: LocalizedError {
    case accessDenied
    case noDefaultCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access was denied. Please enable it in Settings > Privacy > Reminders."
        case .noDefaultCalendar:
            return "No default reminders list is configured."
        }
    }
}