import Foundation
import Combine

/// Service that communicates with the NeuroSync server's social sentiment API endpoints.
@MainActor
final class SocialSentimentService: ObservableObject {

    static let shared = SocialSentimentService()

    // MARK: - Published State

    @Published var dashboard: SocialDashboard?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastFetched: Date?

    // MARK: - Configuration

    var serverBaseURL: String {
        UserDefaults.standard.string(forKey: "server_base_url") ?? AppConfig.serverBaseURL
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - Fetch Dashboard

    /// Fetch the full social sentiment dashboard from the server.
    func fetchDashboard() async {
        isLoading = true
        errorMessage = nil

        guard let url = URL(string: "\(serverBaseURL)/social/dashboard") else {
            errorMessage = "Invalid server URL"
            isLoading = false
            return
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw SocialAPIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                throw SocialAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
            }

            let decoded = try decoder.decode(SocialDashboard.self, from: data)
            dashboard = decoded
            lastFetched = Date()
        } catch let error as SocialAPIError {
            errorMessage = error.localizedDescription
        } catch let decodingError as DecodingError {
            errorMessage = "Data parsing error: \(decodingError.localizedDescription)"
        } catch {
            errorMessage = "Connection failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Fetch Urgent Alerts

    /// Fetch only urgent/crisis messages.
    func fetchUrgentAlerts() async -> UrgentAlertResponse? {
        guard let url = URL(string: "\(serverBaseURL)/social/urgent") else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            return try decoder.decode(UrgentAlertResponse.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Health-Social Correlation

    /// Sends a health stress result to the server for correlation with social stress.
    func postHealthStress(stressLevel: String, confidence: Double) async {
        guard let url = URL(string: "\(serverBaseURL)/social/health-correlation") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "stress_level": stressLevel,
            "confidence": confidence,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, _) = try await session.data(for: request)
        } catch {
            // Non-critical — log but don't surface
            print("Health correlation post failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Social Reminder Creation

    /// If social stress is high, create a reminder via the server.
    func requestSocialReminder(stressLevel: String, reason: String) async -> Bool {
        guard let url = URL(string: "\(serverBaseURL)/social/create-reminder") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "stress_level": stressLevel,
            "reason": reason,
            "source": "social_sentiment",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await session.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool {
                return success
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Fetch Pending Reminders

    /// Poll the server for pending reminders to create locally.
    func fetchPendingReminders() async -> [[String: Any]] {
        guard let url = URL(string: "\(serverBaseURL)/social/pending-reminders") else { return [] }

        do {
            let (data, _) = try await session.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reminders = json["reminders"] as? [[String: Any]] {
                return reminders
            }
            return []
        } catch {
            return []
        }
    }
}

// MARK: - Errors

enum SocialAPIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from the NeuroSync server."
        case .httpError(let code, let body):
            return "Server error (\(code)): \(body.prefix(200))"
        case .notAvailable:
            return "Social sentiment data is not available yet."
        }
    }
}
