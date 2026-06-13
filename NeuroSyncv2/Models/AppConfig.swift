import Foundation

enum AppConfig {
    // NVIDIA NIM API
    static let nvidiaBaseURL = "https://integrate.api.nvidia.com/v1"
    static let nvidiaModel = "nvidia/nemotron-3-ultra-550b-a55b"

    // NeuroSync Server API
    // Use the Mac's local IP so the iPhone can reach it during development.
    static let serverBaseURL = "http://172.18.92.67:8080"

    // Timings
    static let healthFetchInterval: TimeInterval = 300 // 5 min
    static let bgTaskMinimumInterval: TimeInterval = 30 * 60 // 30 min
    static let socialPollInterval: TimeInterval = 30 // 30 seconds

    // Identifiers
    static let bgTaskIdentifier = "com.akshaylakkur.NeuroSyncv2.stressCheck"
    static let apiKeyService = "NeuroSyncv2"
    static let apiKeyAccount = "NVIDIA_API_KEY"

    // UserDefaults keys
    static let stressEventsKey = "stress_events"
    static let bgRefreshEnabledKey = "bg_refresh_enabled"
}