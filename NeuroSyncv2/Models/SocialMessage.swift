import Foundation

/// Represents a single social message with sentiment analysis from the OpenClaw orchestrator.
struct SocialMessage: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let sender: String
    let channel: String
    let timestamp: String
    let isUrgent: Bool
    let isCrisis: Bool
    let sentimentLabel: String

    enum CodingKeys: String, CodingKey {
        case id, text, sender, channel, timestamp
        case isUrgent = "is_urgent"
        case isCrisis = "is_crisis"
        case sentimentLabel = "sentiment_label"
    }

    var formattedTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestamp) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            return rel.localizedString(for: date, relativeTo: Date())
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timestamp) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .abbreviated
            return rel.localizedString(for: date, relativeTo: Date())
        }
        return timestamp
    }

    var senderInitials: String {
        let parts = sender.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].first?.uppercased() ?? "")\(parts[1].first?.uppercased() ?? "")"
        }
        return String(sender.prefix(2)).uppercased()
    }

    var channelIcon: String {
        switch channel.lowercased() {
        case "discord": return "bubble.left.and.bubble.right.fill"
        case "gmail", "email": return "envelope.fill"
        default: return "message.fill"
        }
    }

    var sentimentIcon: String {
        switch sentimentLabel.lowercased() {
        case "positive": return "😊"
        case "negative": return "😟"
        default: return "😐"
        }
    }

    /// Color identifier string for use in view-level color mapping.
    var sentimentColorName: String {
        switch sentimentLabel.lowercased() {
        case "positive": return "green"
        case "negative": return "red"
        default: return "gray"
        }
    }

    var urgencyBadge: String {
        if isCrisis { return "🚨" }
        if isUrgent { return "⚠️" }
        return ""
    }

    static func == (lhs: SocialMessage, rhs: SocialMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// Per-channel sentiment summary from the orchestrator.
struct SentimentSummary: Codable, Identifiable {
    let channel: String
    let messageCount: Int
    let uniqueSenders: Int
    let overallStressLevel: String
    let sentiment: String
    let crisisFlag: Bool
    let urgentCount: Int
    let topThemes: [String]
    let summary: String
    let generatedAt: String

    var id: String { channel }

    enum CodingKeys: String, CodingKey {
        case channel, sentiment, summary
        case messageCount = "message_count"
        case uniqueSenders = "unique_senders"
        case overallStressLevel = "overall_stress_level"
        case crisisFlag = "crisis_flag"
        case urgentCount = "urgent_count"
        case topThemes = "top_themes"
        case generatedAt = "generated_at"
    }

    /// Color identifier string for use in view-level color mapping.
    var stressColorName: String {
        switch overallStressLevel.lowercased() {
        case "critical", "high": return "red"
        case "moderate": return "orange"
        case "low": return "green"
        default: return "gray"
        }
    }
}

/// Top-level dashboard response from the server.
struct SocialDashboard: Codable {
    let lastUpdated: String
    let totalMessagesToday: Int
    let totalUrgent: Int
    let crisisActive: Bool
    let overallMood: String
    let combinedStressLevel: String
    let channels: [SentimentSummary]
    let recentMessages: [SocialMessage]
    let healthSocialCorrelation: String?

    enum CodingKeys: String, CodingKey {
        case lastUpdated = "last_updated"
        case totalMessagesToday = "total_messages_today"
        case totalUrgent = "total_urgent"
        case crisisActive = "crisis_active"
        case overallMood = "overall_mood"
        case combinedStressLevel = "combined_stress_level"
        case channels
        case recentMessages = "recent_messages"
        case healthSocialCorrelation = "health_social_correlation"
    }
}

/// Urgent messages alert response.
struct UrgentAlertResponse: Codable {
    let count: Int
    let crisisActive: Bool
    let messages: [SocialMessage]

    enum CodingKeys: String, CodingKey {
        case count, messages
        case crisisActive = "crisis_active"
    }
}