import SwiftUI

/// Main view for the Social Sentiment tab.
/// Shows real-time sentiment analysis of Discord and Email messages.
struct SocialSentimentView: View {
    @StateObject private var socialVM = SocialSentimentViewModel()
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Error banner
                    if let error = socialVM.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                socialVM.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
                        .padding(.horizontal)
                    }

                    // Crisis Alert Banner
                    if socialVM.crisisActive {
                        crisisBanner
                    }

                    // Overall Sentiment Card
                    overallSentimentCard

                    // Channel Breakdowns
                    if let channels = socialVM.dashboard?.channels, !channels.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Channel Breakdown", systemImage: "chart.bar.fill")
                                .font(.headline)
                                .padding(.horizontal)

                            ForEach(channels) { summary in
                                ChannelBreakdownCard(summary: summary)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    // Recent Messages
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Recent Messages", systemImage: "text.bubble.fill")
                                .font(.headline)
                            Spacer()
                            if !socialVM.messages.isEmpty {
                                Text("\(socialVM.messages.count) msgs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)

                        if socialVM.messages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No messages yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("The OpenClaw orchestrator will poll Discord and Email every 15 seconds.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            ForEach(socialVM.messages) { message in
                                MessageRowView(message: message)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    // Health-Social Correlation
                    if let correlation = socialVM.dashboard?.healthSocialCorrelation {
                        correlationCard(correlation)
                    }

                    // Reminder Creation
                    if socialVM.crisisActive || socialVM.urgentCount > 0 {
                        createReminderButton
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Social Sentiment")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(socialVM.isPolling ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(socialVM.statusText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .refreshable {
                await socialVM.refresh()
                // Also post current health data for correlation
                if let result = dashboardVM.latestResult {
                    await socialVM.postHealthCorrelation(
                        stressLevel: result.stressLevel.rawValue,
                        confidence: result.confidence
                    )
                }
            }
            .onAppear {
                socialVM.startPolling()
            }
            .onDisappear {
                socialVM.stopPolling()
            }
        }
    }

    // MARK: - Crisis Banner

    private var crisisBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.title2)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("CRISIS DETECTED")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Urgent messages detected in your channels. Tap to create a reminder.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()

            Button {
                Task {
                    await socialVM.handleHighSocialStress(
                        stressLevel: socialVM.dashboard?.combinedStressLevel ?? "high",
                        reason: "Crisis detected in social channels: \(socialVM.urgentCount) urgent messages"
                    )
                }
            } label: {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    // MARK: - Overall Sentiment Card

    private var overallSentimentCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Overall Sentiment", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                if socialVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            HStack(spacing: 24) {
                // Stress Level
                VStack(spacing: 4) {
                    Text(socialVM.combinedStressDisplay)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(stressColor(socialVM.dashboard?.combinedStressLevel ?? "none"))
                    Text("Stress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                // Messages
                VStack(spacing: 4) {
                    Text("\(socialVM.dashboard?.totalMessagesToday ?? 0)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Text("Messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 40)

                // Urgent
                VStack(spacing: 4) {
                    Text("\(socialVM.urgentCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(socialVM.urgentCount > 0 ? .red : .secondary)
                    Text("Urgent")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Mood indicator
            if let mood = socialVM.dashboard?.overallMood {
                HStack {
                    Text("Mood: ")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(mood.capitalized)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(moodColor(mood))
                    Text(moodIcon(mood))
                        .font(.subheadline)
                }
            }

            if let last = socialVM.lastUpdated {
                Text("Last updated: \(relativeTime(from: last))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
        .padding(.horizontal)
    }

    // MARK: - Correlation Card

    private func correlationCard(_ text: String) -> some View {
        HStack {
            Image(systemName: "link.circle.fill")
                .foregroundColor(.indigo)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.06)))
        .padding(.horizontal)
    }

    // MARK: - Create Reminder Button

    private var createReminderButton: some View {
        Button {
            Task {
                await socialVM.handleHighSocialStress(
                    stressLevel: socialVM.dashboard?.combinedStressLevel ?? "high",
                    reason: "Social stress triggered by \(socialVM.urgentCount) urgent message(s)"
                )
            }
        } label: {
            HStack {
                Image(systemName: "bell.badge.fill")
                Text("Create Stress Reminder")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private func stressColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "critical", "high": return .red
        case "moderate": return .orange
        case "low": return .green
        default: return .secondary
        }
    }

    private func moodColor(_ mood: String) -> Color {
        switch mood.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default: return .secondary
        }
    }

    private func moodIcon(_ mood: String) -> String {
        switch mood.lowercased() {
        case "positive": return "😊"
        case "negative": return "😟"
        default: return "😐"
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    SocialSentimentView()
        .environmentObject(DashboardViewModel())
}