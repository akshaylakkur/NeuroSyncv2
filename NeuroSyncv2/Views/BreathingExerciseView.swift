import SwiftUI
import Combine

struct BreathingExerciseView: View {
    let plan: StressExercisePlan
    let onDismiss: () -> Void

    @StateObject private var exerciseManager = StressExerciseManager()

    @State private var circleScale: CGFloat = 0.5
    @State private var circleOpacity: CGFloat = 0.8
    @State private var gradientPhase: CGFloat = 0
    @State private var showCompletion = false

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Animated gradient background
            backgroundGradient
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: gradientPhase)

            // Content
            VStack(spacing: 0) {

                // MARK: - Top Bar
                HStack {
                    if case .completed = exerciseManager.state {
                        // No "End" during completion overlay; it auto-dismisses
                    } else {
                        Button {
                            exerciseManager.stopExercise()
                            onDismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                Text("End")
                                    .font(.body)
                            }
                            .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    if case .paused = exerciseManager.state {
                        Button {
                            exerciseManager.resumeExercise()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("Resume")
                                    .font(.body)
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }
                    } else if case .active = exerciseManager.state {
                        Button {
                            exerciseManager.pauseExercise()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pause.circle.fill")
                                    .font(.title3)
                                Text("Pause")
                                    .font(.body)
                            }
                            .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

                // MARK: - Exercise Name
                Text(plan.name)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 8)

                // MARK: - Breathing Circle + Phase Info
                if case .completed = exerciseManager.state {
                    // Completion state
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)

                        Text("Exercise Complete!")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Great job taking care of your stress.")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .transition(.opacity.combined(with: .scale))
                } else if case let .active(index, remaining) = exerciseManager.state {
                    VStack(spacing: 28) {

                        // Animated breathing circle
                        ZStack {
                            // Outer glow
                            Circle()
                                .stroke(currentPhase(index).map { phaseColor($0.type) } ?? .white.opacity(0.2), lineWidth: 2)
                                .scaleEffect(circleScale * 1.15)
                                .opacity(circleOpacity * 0.3)

                            // Inner circle
                            Circle()
                                .fill(currentPhase(index).map { phaseColor($0.type) } ?? .white.opacity(0.3))
                                .scaleEffect(circleScale)
                                .opacity(circleOpacity)
                                .animation(.easeInOut(duration: Double(plan.phases[index].durationSeconds)),
                                           value: circleScale)
                                .animation(.easeInOut(duration: Double(plan.phases[index].durationSeconds)),
                                           value: circleOpacity)
                        }
                        .frame(width: 220, height: 220)

                        // Phase instruction
                        if let phase = currentPhase(index) {
                            Text(phase.instruction)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                .id(phase.type.rawValue + String(phase.durationSeconds))
                        }

                        // Countdown timer
                        Text("\(remaining)")
                            .font(.system(size: 72, weight: .thin, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .contentTransition(.numericText())
                            .animation(.default, value: remaining)
                    }
                } else if case .paused = exerciseManager.state {
                    // Paused overlay
                    VStack(spacing: 20) {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 70))
                            .foregroundColor(.white.opacity(0.7))

                        Text("Exercise Paused")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Button {
                            exerciseManager.resumeExercise()
                        } label: {
                            Text("Tap to Resume")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                    }
                }

                Spacer()

                // MARK: - Progress Bar
                if case .completed = exerciseManager.state {
                    // Completion auto-dismiss
                } else {
                    VStack(spacing: 8) {
                        ProgressView(
                            value: Double(exerciseManager.totalElapsedSeconds),
                            total: Double(plan.totalDurationSeconds)
                        )
                        .tint(.white.opacity(0.5))
                        .background(
                            ProgressView(value: Double(exerciseManager.totalElapsedSeconds),
                                         total: Double(plan.totalDurationSeconds))
                                .tint(.white.opacity(0.15))
                        )

                        Text("\(formatDuration(exerciseManager.totalElapsedSeconds)) / \(formatDuration(plan.totalDurationSeconds))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 12)
                }

                // MARK: - Skip / Controls
                if case .active = exerciseManager.state {
                    Button {
                        withAnimation {
                            exerciseManager.skipToNextPhase()
                        }
                    } label: {
                        Text("Skip Phase")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.bottom, 40)
                } else if case .paused = exerciseManager.state {
                    Button {
                        exerciseManager.stopExercise()
                        onDismiss()
                    } label: {
                        Text("End Exercise")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.bottom, 40)
                } else {
                    Color.clear
                        .frame(height: 20)
                        .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            exerciseManager.startExercise(plan: plan)
        }
        .onDisappear {
            exerciseManager.stopExercise()
        }
        .onChange(of: exerciseManager.state) { _, newState in
            switch newState {
            case .active(let index, _):
                withAnimation(.easeInOut(duration: Double(plan.phases[safe: index]?.durationSeconds ?? 4))) {
                    updateCircleAnimation(for: plan.phases[safe: index]?.type ?? .inhale)
                }
            case .completed:
                withAnimation(.easeInOut(duration: 0.5)) {
                    showCompletion = true
                }
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    onDismiss()
                }
            default:
                break
            }
        }
        .onReceive(timer) { _ in
            gradientPhase += 0.003
        }
        .animation(.easeInOut(duration: 2), value: showCompletion)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.02, blue: 0.15),
                Color(red: 0.08, green: 0.05, blue: 0.25),
                Color(red: 0.12, green: 0.08, blue: 0.20),
                Color(red: 0.06, green: 0.03, blue: 0.28),
                Color(red: 0.05, green: 0.02, blue: 0.15),
            ]),
            center: .center,
            angle: .degrees(Double(gradientPhase * 360).truncatingRemainder(dividingBy: 360))
        )
    }

    // MARK: - Helpers

    private func currentPhase(_ index: Int) -> StressExercisePhase? {
        guard index < plan.phases.count else { return nil }
        return plan.phases[index]
    }

    private func phaseColor(_ type: StressExercisePhaseType) -> Color {
        switch type {
        case .inhale:  return Color(red: 0.3, green: 0.7, blue: 0.9) // Calm blue
        case .hold:    return Color(red: 0.4, green: 0.8, blue: 0.5) // Soft green
        case .exhale:  return Color(red: 0.6, green: 0.4, blue: 0.8) // Gentle purple
        case .rest:    return Color(red: 0.5, green: 0.5, blue: 0.6) // Muted lavender
        }
    }

    private func updateCircleAnimation(for type: StressExercisePhaseType) {
        switch type {
        case .inhale:
            circleScale = 1.0
            circleOpacity = 0.9
        case .hold:
            circleScale = 1.0
            circleOpacity = 0.7
        case .exhale:
            circleScale = 0.4
            circleOpacity = 0.5
        case .rest:
            circleScale = 0.3
            circleOpacity = 0.3
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }
}

// MARK: - Safe Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// MARK: - Preview

#Preview {
    BreathingExerciseView(
        plan: StressExerciseManager.fallbackPlan,
        onDismiss: {}
    )
}