import Foundation
import Combine

@MainActor
final class StressHistoryViewModel: ObservableObject {

    @Published var stressEvents: [StressEvent] = []
    @Published var searchQuery = ""
    @Published var selectedStressLevel: StressLevel?

    var filteredEvents: [StressEvent] {
        var events = stressEvents

        if let level = selectedStressLevel {
            events = events.filter { $0.result.stressLevel == level }
        }

        if !searchQuery.isEmpty {
            events = events.filter { event in
                event.result.reasoning.localizedCaseInsensitiveContains(searchQuery)
                    || event.result.suggestion.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        return events
    }

    var groupedByDate: [(Date, [StressEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    func loadEvents() {
        stressEvents = BackgroundTaskService.loadEvents()
    }

    func refresh() {
        loadEvents()
    }
}