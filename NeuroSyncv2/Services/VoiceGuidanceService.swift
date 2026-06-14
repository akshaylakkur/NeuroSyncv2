import Foundation
import Combine
import AVFoundation

/// Service for providing voice guidance during breathing exercises.
/// Uses AVSpeechSynthesizer for text-to-speech — no microphone permission required.
@MainActor
final class VoiceGuidanceService: ObservableObject {

    static let shared = VoiceGuidanceService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        configureAudioSession()
    }

    /// Configures the audio session to play speech even when the device is in silent mode.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Audio session configuration is non-critical — speech may be silent
            // if the device is in silent mode, but the exercise UI still works.
            print("VoiceGuidanceService: Audio session setup failed — \(error.localizedDescription)")
        }
    }

    @Published var isSpeaking = false
    @Published var currentUtterance: String?

    // MARK: - Public API

    /// Speaks the given text with a calming voice configuration.
    /// - Parameters:
    ///   - text: The text to speak aloud.
    ///   - rate: Speech rate. Default 0.45 (slower than default ~0.5 for calmness).
    ///   - pitchMultiplier: Voice pitch. Default 1.1 (slightly warmer).
    ///   - volume: Output volume. Default 0.8.
    func speak(_ text: String, rate: Float = 0.45, pitchMultiplier: Float = 1.1, volume: Float = 0.8) {
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.15

        currentUtterance = text
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Stops any ongoing speech immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentUtterance = nil
    }

    /// Pauses speech at the current word boundary.
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
        isSpeaking = false
    }

    /// Resumes paused speech.
    func resume() {
        synthesizer.continueSpeaking()
        isSpeaking = true
    }
}