import Foundation
import Combine
import AVFoundation

/// State machine that manages a guided breathing exercise with timer-driven phase transitions
/// and voice guidance integration.
@MainActor
final class StressExerciseManager: ObservableObject {

    // MARK: - State Machine

    enum ExerciseState: Equatable {
        case idle
        case active(phaseIndex: Int, phaseTimeRemaining: Int)
        case paused(phaseIndex: Int, phaseTimeRemaining: Int)
        case completed
    }

    // MARK: - Published State

    @Published var state: ExerciseState = .idle
    @Published var currentPlan: StressExercisePlan?
    @Published var totalElapsedSeconds: Int = 0

    // MARK: - Services

    private let voiceService = VoiceGuidanceService.shared

    // MARK: - Timers

    private var phaseTimer: Timer?

    // MARK: - Fallback Plan

    /// A safe 4-7-8 breathing plan used when the LLM fails to generate a personalized plan.
    static let fallbackPlan = StressExercisePlan(
        name: "4-7-8 Calm Breathing",
        phases: [
            StressExercisePhase(type: .inhale, durationSeconds: 4, instruction: "Breathe in slowly through your nose", voicePrompt: "Breathe in..."),
            StressExercisePhase(type: .hold, durationSeconds: 7, instruction: "Hold your breath gently", voicePrompt: "Hold..."),
            StressExercisePhase(type: .exhale, durationSeconds: 8, instruction: "Breathe out slowly through your mouth", voicePrompt: "Breathe out slowly..."),
            StressExercisePhase(type: .inhale, durationSeconds: 4, instruction: "Breathe in slowly through your nose", voicePrompt: "Breathe in..."),
            StressExercisePhase(type: .hold, durationSeconds: 7, instruction: "Hold your breath gently", voicePrompt: "Hold..."),
            StressExercisePhase(type: .exhale, durationSeconds: 8, instruction: "Breathe out slowly through your mouth", voicePrompt: "Breathe out slowly..."),
        ],
        spokenSummary: "I've prepared a calming 4-7-8 breathing exercise for you. Breathe in for 4 seconds, hold for 7, and exhale for 8. Follow along in the app."
    )

    // MARK: - Public API

    /// Start the exercise with the given plan.
    /// If an exercise is already in progress it is stopped first.
    func startExercise(plan: StressExercisePlan) {
        stopExercise()
        currentPlan = plan
        totalElapsedSeconds = 0
        state = .active(phaseIndex: 0, phaseTimeRemaining: plan.phases[0].durationSeconds)
        speakPhase(plan.phases[0])
        startPhaseTimer(for: plan.phases[0], phaseIndex: 0)
    }

    /// Pause the active exercise.
    func pauseExercise() {
        guard case let .active(index, remaining) = state else { return }
        state = .paused(phaseIndex: index, phaseTimeRemaining: remaining)
        invalidateTimers()
        voiceService.pause()
    }

    /// Resume a paused exercise.
    func resumeExercise() {
        guard case let .paused(index, remaining) = state,
              let plan = currentPlan,
              index < plan.phases.count else { return }
        state = .active(phaseIndex: index, phaseTimeRemaining: remaining)
        resumePhaseTimer(phase: plan.phases[index], phaseIndex: index, remainingSeconds: remaining)
        voiceService.resume()
    }

    /// Stop the exercise entirely and reset all state.
    func stopExercise() {
        invalidateTimers()
        voiceService.stop()
        state = .idle
        totalElapsedSeconds = 0
        currentPlan = nil
    }

    /// Skip the current phase and advance to the next one.
    func skipToNextPhase() {
        guard currentPlan != nil else { return }
        invalidateTimers()
        advanceToNextPhase()
    }

    // MARK: - Timer Management

    private func startPhaseTimer(for phase: StressExercisePhase, phaseIndex: Int) {
        phaseTimer?.invalidate()
        var remaining = phase.durationSeconds
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            remaining -= 1
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.totalElapsedSeconds += 1
                if remaining <= 0 {
                    self.advanceToNextPhase()
                } else {
                    self.state = .active(phaseIndex: phaseIndex, phaseTimeRemaining: remaining)
                }
            }
        }
    }

    private func resumePhaseTimer(phase: StressExercisePhase, phaseIndex: Int, remainingSeconds: Int) {
        phaseTimer?.invalidate()
        var remaining = remainingSeconds
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            remaining -= 1
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.totalElapsedSeconds += 1
                if remaining <= 0 {
                    self.advanceToNextPhase()
                } else {
                    self.state = .active(phaseIndex: phaseIndex, phaseTimeRemaining: remaining)
                }
            }
        }
    }

    private func advanceToNextPhase() {
        guard let plan = currentPlan else { return }

        let currentIndex: Int
        switch state {
        case .active(let idx, _), .paused(let idx, _):
            currentIndex = idx
        default:
            currentIndex = -1
        }

        let nextIndex = currentIndex + 1

        guard nextIndex < plan.phases.count else {
            completeExercise()
            return
        }

        let nextPhase = plan.phases[nextIndex]
        state = .active(phaseIndex: nextIndex, phaseTimeRemaining: nextPhase.durationSeconds)
        speakPhase(nextPhase)
        startPhaseTimer(for: nextPhase, phaseIndex: nextIndex)
    }

    private func completeExercise() {
        invalidateTimers()
        voiceService.stop()
        state = .completed
        // Keep currentPlan around so the view can show completion state
    }

    // MARK: - Voice Guidance

    private func speakPhase(_ phase: StressExercisePhase) {
        voiceService.speak(phase.voicePrompt)
    }

    // MARK: - Cleanup

    private func invalidateTimers() {
        phaseTimer?.invalidate()
        phaseTimer = nil
    }

    deinit {
        phaseTimer?.invalidate()
    }
}