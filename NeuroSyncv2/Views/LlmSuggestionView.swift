import SwiftUI

struct LlmSuggestionView: View {
    let suggestion: String?
    let reasoning: String?
    let isLoading: Bool
    let lastUpdated: Date?
    let onRefresh: () -> Void

    @State private var animateText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.indigo)
                    .font(.title3)
                Text("AI Insights")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .disabled(isLoading)
            }

            if isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Analyzing your vitals...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ProgressView()
                        .tint(.indigo)
                }
                .padding(.vertical, 8)
            } else if let suggestion = suggestion {
                // Suggestion
                VStack(alignment: .leading, spacing: 6) {
                    Label("Suggestion", systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text(suggestion)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .opacity(animateText ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: animateText)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.08))
                )

                // Reasoning
                if let reasoning = reasoning {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Analysis", systemImage: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.purple)

                        Text(reasoning)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.06))
                    )
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Pull down to refresh or tap the refresh button to analyze your current metrics.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }

            // Last updated
            if let lastUpdated = lastUpdated {
                Text("Last analyzed: \(relativeTime(from: lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .onAppear {
            animateText = true
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    VStack(spacing: 20) {
        LlmSuggestionView(
            suggestion: "Try a 5-minute breathing exercise: inhale for 4 seconds, hold for 4, exhale for 6.",
            reasoning: "Elevated heart rate (88 bpm) combined with low HRV (24ms) and reduced sleep (5.2h) suggests moderate stress response.",
            isLoading: false,
            lastUpdated: Date().addingTimeInterval(-300),
            onRefresh: {}
        )
        LlmSuggestionView(
            suggestion: nil,
            reasoning: nil,
            isLoading: true,
            lastUpdated: nil,
            onRefresh: {}
        )
        LlmSuggestionView(
            suggestion: nil,
            reasoning: nil,
            isLoading: false,
            lastUpdated: nil,
            onRefresh: {}
        )
    }
    .padding()
}