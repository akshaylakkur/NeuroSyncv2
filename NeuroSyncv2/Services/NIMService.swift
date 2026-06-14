import Foundation

/// Service for calling the NVIDIA NIM OpenAI-compatible chat completions API.
final class NIMService: @unchecked Sendable {

    static let shared = NIMService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private let decoder = JSONDecoder()

    // MARK: - Stress Analysis

    /// Sends the health metrics to NVIDIA NIM for stress analysis.
    /// - Parameters:
    ///   - metrics: The current health metrics snapshot.
    ///   - apiKey: NVIDIA API key.
    /// - Returns: Parsed StressResult from the LLM.
    func analyzeStress(metrics: HealthMetrics, apiKey: String) async throws -> StressResult {
        let prompt = buildPrompt(from: metrics)
        let requestBody = ChatCompletionRequest(
            model: AppConfig.nvidiaModel,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: prompt),
            ],
            temperature: 0.3,
            top_p: 0.95,
            max_tokens: 1024,
            extra_body: ChatCompletionRequest.ExtraBody(
                chat_template_kwargs: ChatCompletionRequest.ChatTemplateKwargs(enable_thinking: false),
                reasoning_budget: nil
            )
        )

        var request = URLRequest(url: URL(string: "\(AppConfig.nvidiaBaseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NIMError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NIMError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let apiResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

        guard let content = apiResponse.choices?.first?.message?.content else {
            throw NIMError.emptyResponse
        }

        return try parseResult(from: content)
    }

    // MARK: - Prompt Construction

    private let systemPrompt = """
    You are a medical stress analysis AI. Given the user's current health metrics, determine their stress level.

    Rules:
    - Low HRV (below 30ms) combined with elevated resting heart rate is a strong stress indicator.
    - Poor sleep (under 6h) significantly contributes to stress.
    - Low exercise and low mindful minutes are contributing factors.
    - Elevated respiratory rate (above 16 bpm at rest) can indicate stress.
    - Be evidence-based and conservative — don't flag stress without supporting data.

    Respond ONLY with valid JSON in this exact format (no markdown, no code fences):
    {"stressLevel":"low|moderate|high|critical","confidence":0.0-1.0,"reasoning":"brief clinical reasoning","suggestion":"actionable short suggestion"}
    """

    private func buildPrompt(from metrics: HealthMetrics) -> String {
        let dict = metrics.llmRepresentation
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "No metrics available."
        }
        return jsonString
    }

    // MARK: - Response Parsing

    private func parseResult(from content: String) throws -> StressResult {
        // The model might wrap JSON in markdown code fences — strip those.
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` or ``` ... ```
        if cleaned.hasPrefix("```") {
            cleaned = cleaned.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("json") {
                cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw NIMError.parseFailure(raw: cleaned)
        }

        do {
            let result = try decoder.decode(StressResult.self, from: data)
            return result
        } catch {
            throw NIMError.parseFailure(raw: cleaned)
        }
    }

    // MARK: - Exercise Generation

    private let exerciseSystemPrompt = """
    You are a stress relief breathing exercise designer. Given the user's health metrics and their current stress analysis, design a personalized breathing exercise plan.

    Rules:
    - Higher heart rate (>90 bpm) = longer exhale phases (exhale should be 2x inhale)
    - Low HRV (<25ms) = gentler rhythm, shorter holds, more rest phases
    - Exercise should be 2-5 minutes total (120-300 seconds)
    - Phase durations in whole seconds only
    - Each phase MUST be one of: inhale, hold, exhale, rest
    - Voice prompts should be calming, 2-8 words
    - Include at least 2 cycles (inhale → hold → exhale → rest repeated)

    Respond ONLY with valid JSON in this exact format (no markdown, no code fences):
    {"name":"short calming name","phases":[{"type":"inhale|hold|exhale|rest","durationSeconds":4,"instruction":"Breathe in through your nose","voicePrompt":"Breathe in..."}],"spokenSummary":"A brief natural-language summary that Siri will speak aloud. Example: Your heart rate is elevated and your HRV indicates stress. I've designed a 3-minute exercise called Ocean Breaths for you — with gentle 4-second inhales and slow 6-second exhales."}
    """

    /// Generates a personalized breathing/stress-relief exercise plan based on current health metrics and stress analysis.
    /// - Parameters:
    ///   - metrics: The current health metrics snapshot.
    ///   - stressResult: The stress analysis result that triggered this exercise.
    ///   - apiKey: NVIDIA API key.
    /// - Returns: A StressExercisePlan with named phases and durations.
    func generateExercise(metrics: HealthMetrics, stressResult: StressResult, apiKey: String) async throws -> StressExercisePlan {
        let metricsJSON = buildMetricsJSON(metrics)
        let prompt = """
        Current health metrics:
        \(metricsJSON)

        Current stress analysis:
        Level: \(stressResult.stressLevel.rawValue)
        Confidence: \(stressResult.confidence)
        Reasoning: \(stressResult.reasoning)
        Suggestion: \(stressResult.suggestion)

        Design a personalized breathing exercise based on this data.
        """

        let requestBody = ChatCompletionRequest(
            model: AppConfig.nvidiaModel,
            messages: [
                .init(role: "system", content: exerciseSystemPrompt),
                .init(role: "user", content: prompt),
            ],
            temperature: 0.5,
            top_p: 0.95,
            max_tokens: 1024,
            extra_body: ChatCompletionRequest.ExtraBody(
                chat_template_kwargs: ChatCompletionRequest.ChatTemplateKwargs(enable_thinking: false),
                reasoning_budget: nil
            )
        )

        var request = URLRequest(url: URL(string: "\(AppConfig.nvidiaBaseURL)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NIMError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw NIMError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let apiResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

        guard let content = apiResponse.choices?.first?.message?.content else {
            throw NIMError.emptyResponse
        }

        return try parseExerciseResult(from: content)
    }

    private func parseExerciseResult(from content: String) throws -> StressExercisePlan {
        // Strip markdown code fences like parseResult does
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasPrefix("```") {
            cleaned = cleaned.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("json") {
                cleaned = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let data = cleaned.data(using: .utf8) else {
            throw NIMError.parseFailure(raw: cleaned)
        }

        let plan = try decoder.decode(StressExercisePlan.self, from: data)

        // Validate plan — must have at least 3 phases and total duration between 60-300s
        guard plan.phases.count >= 3 else {
            throw NIMError.parseFailure(raw: "Exercise plan has fewer than 3 phases")
        }

        let total = plan.totalDurationSeconds
        guard total >= 60, total <= 300 else {
            throw NIMError.parseFailure(raw: "Exercise plan duration \(total)s outside valid range (60-300s)")
        }

        return plan
    }

    private func buildMetricsJSON(_ metrics: HealthMetrics) -> String {
        let dict = metrics.llmRepresentation
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8) else {
            return "No metrics available."
        }
        return str
    }
}

// MARK: - API Types

/// OpenAI-compatible chat completion request body.
private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let top_p: Double
    let max_tokens: Int
    let extra_body: ExtraBody?

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ExtraBody: Encodable {
        let chat_template_kwargs: ChatTemplateKwargs?
        let reasoning_budget: Int?
    }

    struct ChatTemplateKwargs: Encodable {
        let enable_thinking: Bool
    }
}

/// OpenAI-compatible chat completion response.
private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message?
    }
    let choices: [Choice]?
}

// MARK: - Errors

enum NIMError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case emptyResponse
    case parseFailure(raw: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from the NVIDIA NIM API."
        case .httpError(let code, let body):
            return "NVIDIA API error (\(code)): \(body.prefix(200))"
        case .emptyResponse:
            return "The NVIDIA API returned an empty response."
        case .parseFailure(let raw):
            return "Failed to parse LLM response: \(raw.prefix(300))"
        }
    }
}