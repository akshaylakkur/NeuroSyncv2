import SwiftUI

/// Card showing sentiment breakdown for a single channel (Discord, Gmail, etc.)
struct ChannelBreakdownCard: View {
    let summary: SentimentSummary

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: channelIcon(summary.channel))
                    .font(.title3)
                    .foregroundColor(channelColor(summary.channel))
                Text(summary.channel.capitalized)
                    .font(.headline)
                Spacer()
                Text(summary.overallStressLevel.uppercased())
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stressBadgeColor)
                    .clipShape(Capsule())
            }

            // Stats row
            HStack(spacing: 16) {
                statItem(value: "\(summary.messageCount)", label: "Messages", icon: "message.fill", color: .blue)
                statItem(value: "\(summary.uniqueSenders)", label: "Senders", icon: "person.2.fill", color: .green)
                statItem(value: "\(summary.urgentCount)", label: "Urgent", icon: "exclamationmark.triangle.fill", color: .orange)
            }

            // Themes
            if !summary.topThemes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Themes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(summary.topThemes, id: \.self) { theme in
                            Text(theme)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.1))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Summary text
            if !summary.summary.isEmpty {
                Text(summary.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    // MARK: - Sub-views

    private func statItem(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var stressBadgeColor: Color {
        switch summary.overallStressLevel.lowercased() {
        case "critical", "high": return .red
        case "moderate": return .orange
        case "low": return .green
        default: return .gray
        }
    }

    private func channelIcon(_ channel: String) -> String {
        switch channel.lowercased() {
        case "discord": return "bubble.left.and.bubble.right.fill"
        case "gmail", "email": return "envelope.fill"
        default: return "message.fill"
        }
    }

    private func channelColor(_ channel: String) -> Color {
        switch channel.lowercased() {
        case "discord": return .indigo
        case "gmail", "email": return .red
        default: return .blue
        }
    }
}

// MARK: - Flow Layout

/// Simple flow layout that wraps items to the next line when they overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for size in sizes {
            if lineWidth + size.width + spacing > (proposal.width ?? .infinity) {
                width = max(width, lineWidth)
                height += lineHeight + spacing
                lineWidth = size.width + spacing
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
        }
        width = max(width, lineWidth)
        height += lineHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

#Preview {
    ChannelBreakdownCard(
        summary: SentimentSummary(
            channel: "discord",
            messageCount: 42,
            uniqueSenders: 8,
            overallStressLevel: "moderate",
            sentiment: "negative",
            crisisFlag: false,
            urgentCount: 3,
            topThemes: ["deployment", "bug-fix", "customer-support"],
            summary: "Team communication shows moderate stress with deployment issues.",
            generatedAt: "2026-06-13T12:00:00Z"
        )
    )
    .padding()
}