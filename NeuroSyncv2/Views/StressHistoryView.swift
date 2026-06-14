import SwiftUI

struct StressHistoryView: View {
    @StateObject private var historyVM = StressHistoryViewModel()
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChipsView
                eventsListView
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("History")
            .onAppear {
                historyVM.stressEvents = dashboardVM.stressEvents
            }
            .onChange(of: dashboardVM.stressEvents) { _, newEvents in
                historyVM.stressEvents = newEvents
            }
        }
    }

    private var filterChipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: historyVM.selectedStressLevel == nil) {
                    historyVM.selectedStressLevel = nil
                }
                ForEach(StressLevel.allCases, id: \.self) { level in
                    FilterChip(
                        title: level.rawValue.capitalized,
                        isSelected: historyVM.selectedStressLevel == level,
                        color: color(for: level)
                    ) {
                        historyVM.selectedStressLevel = level
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var eventsListView: some View {
        Group {
            if historyVM.filteredEvents.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "brain")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Stress Events")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Text("Your analysis history will appear here after the first stress check.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(historyVM.groupedByDate, id: \.0) { date, events in
                        Section {
                            ForEach(events) { event in
                                NavigationLink {
                                    StressEventDetailView(event: event)
                                } label: {
                                    StressEventRow(event: event)
                                }
                            }
                            .onDelete { indexSet in
                                deleteEvents(at: indexSet, from: events)
                            }
                        } header: {
                            Text(date, format: .dateTime.weekday().month().day().year())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func deleteEvents(at indexSet: IndexSet, from sectionEvents: [StressEvent]) {
        for index in indexSet {
            let eventToDelete = sectionEvents[index]
            if let idx = historyVM.stressEvents.firstIndex(of: eventToDelete) {
                historyVM.stressEvents.remove(at: idx)
            }
        }
        dashboardVM.stressEvents = historyVM.stressEvents
        BackgroundTaskService.saveEvents(historyVM.stressEvents)
    }

    private func color(for level: StressLevel) -> Color {
        switch level {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .critical: return Color(red: 0.5, green: 0.0, blue: 0.0)
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.15) : Color(.systemGray6))
                .foregroundColor(isSelected ? color : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
    }
}

// MARK: - Event Row

struct StressEventRow: View {
    let event: StressEvent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(badgeIcon)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.result.stressLevel.rawValue.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(badgeColor)

                    if event.reminderCreated {
                        Label("Reminder sent", systemImage: "bell.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Text(event.result.reasoning)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text(event.date, style: .time)
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(Int(event.result.confidence * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(badgeColor)
                Text("confidence")
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }

    private var badgeColor: Color {
        switch event.result.stressLevel {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .critical: return Color(red: 0.5, green: 0.0, blue: 0.0)
        }
    }

    private var badgeIcon: String {
        switch event.result.stressLevel {
        case .low: return "🧘"
        case .moderate: return "⚡"
        case .high: return "🔥"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Event Detail

struct StressEventDetailView: View {
    let event: StressEvent

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(badgeIcon)
                        .font(.system(size: 48))
                    Text(event.result.stressLevel.rawValue.capitalized)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(badgeColor)
                    Text("Confidence: \(Int(event.result.confidence * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(event.date, style: .date)
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.6))
                    Text(event.date, style: .time)
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Analysis", icon: "text.magnifyingglass")
                    Text(event.result.reasoning)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Suggestion", icon: "lightbulb.fill", color: .orange)
                    Text(event.result.suggestion)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.06)))

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Health Metrics", icon: "heart.text.clipboard")
                    MetricRow(label: "Heart Rate", value: event.metrics.heartRate.map({ "\(Int($0)) bpm" }) ?? "N/A")
                    MetricRow(label: "HRV", value: event.metrics.hrv.map({ "\(Int($0)) ms" }) ?? "N/A")
                    MetricRow(label: "Sleep", value: event.metrics.sleepHours.map({ String(format: "%.1f", $0) + " hours" }) ?? "N/A")
                    MetricRow(label: "Steps", value: event.metrics.steps.map({ "\($0)" }) ?? "N/A")
                    MetricRow(label: "Exercise", value: event.metrics.exerciseMinutes.map({ "\(Int($0)) min" }) ?? "N/A")
                    MetricRow(label: "Mindfulness", value: event.metrics.mindfulMinutes.map({ "\(Int($0)) min" }) ?? "N/A")
                    MetricRow(label: "Resp. Rate", value: event.metrics.respiratoryRate.map({ String(format: "%.1f", $0) + " br/min" }) ?? "N/A")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

                if event.reminderCreated {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.orange)
                        Text("A reminder was created in the Reminders app")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.06)))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var badgeColor: Color {
        switch event.result.stressLevel {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .critical: return Color(red: 0.5, green: 0.0, blue: 0.0)
        }
    }

    private var badgeIcon: String {
        switch event.result.stressLevel {
        case .low: return "🧘"
        case .moderate: return "⚡"
        case .high: return "🔥"
        case .critical: return "🚨"
        }
    }
}

// MARK: - Shared Helpers

struct SectionHeader: View {
    let title: String
    let icon: String
    var color: Color = .accentColor

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(color)
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    StressHistoryView()
        .environmentObject(DashboardViewModel())
}