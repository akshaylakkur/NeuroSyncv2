import SwiftUI

/// A single message row showing channel, sender, content preview, sentiment, and urgency.
struct MessageRowView: View {
    let message: SocialMessage

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Avatar / initials
                ZStack {
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 40, height: 40)
                    Text(message.senderInitials)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Header
                    HStack(spacing: 6) {
                        Image(systemName: message.channelIcon)
                            .font(.caption2)
                            .foregroundColor(channelColor)
                        Text(message.sender)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(message.urgencyBadge)
                            .font(.caption)
                        Text(message.sentimentIcon)
                            .font(.caption)
                    }

                    // Message text
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    // Footer
                    HStack(spacing: 8) {
                        Text(message.formattedTime)
                            .font(.caption2)
                            .foregroundColor(Color.secondary.opacity(0.6))
                        Spacer()
                        Text(message.channel.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(channelColor.opacity(0.1))
                            .foregroundColor(channelColor)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(messageBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: message.isCrisis ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            MessageDetailView(message: message)
        }
    }

    // MARK: - Helpers

    private var avatarColor: Color {
        if message.isCrisis { return .red }
        if message.isUrgent { return .orange }
        switch message.sentimentLabel.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default: return .gray
        }
    }

    private var channelColor: Color {
        switch message.channel.lowercased() {
        case "discord": return .indigo
        case "gmail", "email": return .red
        default: return .blue
        }
    }

    private var messageBackground: Color {
        if message.isCrisis { return Color.red.opacity(0.06) }
        if message.isUrgent { return Color.orange.opacity(0.06) }
        return Color(.systemGray6)
    }

    private var borderColor: Color {
        if message.isCrisis { return Color.red.opacity(0.3) }
        if message.isUrgent { return Color.orange.opacity(0.2) }
        return Color.clear
    }
}

// MARK: - Message Detail Sheet

struct MessageDetailView: View {
    let message: SocialMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(avatarColor)
                                .frame(width: 60, height: 60)
                            Text(message.senderInitials)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        Text(message.sender)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(message.channel.capitalized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Status badges
                    HStack(spacing: 8) {
                        if message.isCrisis {
                            Label("Crisis", systemImage: "exclamationmark.octagon.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                        if message.isUrgent {
                            Label("Urgent", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .clipShape(Capsule())
                        }
                        Label(message.sentimentLabel.capitalized, systemImage: "face.smiling")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(sentimentColor)
                            .clipShape(Capsule())
                    }

                    // Message body
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.headline)
                        Text(message.text)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Metadata", systemImage: "info.circle")
                            .font(.headline)
                        metadataRow("Channel", message.channel.capitalized)
                        metadataRow("Sentiment", message.sentimentLabel.capitalized)
                        metadataRow("Timestamp", message.formattedTime)
                        metadataRow("Message ID", message.id.prefix(16).debugDescription)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Message Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var avatarColor: Color {
        if message.isCrisis { return .red }
        if message.isUrgent { return .orange }
        switch message.sentimentLabel.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default: return .gray
        }
    }

    private var sentimentColor: Color {
        switch message.sentimentLabel.lowercased() {
        case "positive": return .green
        case "negative": return .red
        default: return .gray
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
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
    VStack {
        MessageRowView(
            message: SocialMessage(
                id: "123",
                text: "URGENT: Production is DOWN! Need immediate rollback. This is a critical issue affecting all users.",
                sender: "Alice Johnson",
                channel: "discord",
                timestamp: "2026-06-13T12:00:00Z",
                isUrgent: true,
                isCrisis: true,
                sentimentLabel: "negative"
            )
        )
        .padding()
        Spacer()
    }
}