import SwiftUI

struct StressIndicatorView: View {
    let stressLevel: StressLevel?
    let confidence: Double?
    let isAnimating: Bool

    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)
                    .frame(width: 160, height: 160)

                // Active ring
                Circle()
                    .trim(from: 0, to: fillAmount)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.green, .yellow, .orange, .red]),
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.0), value: fillAmount)

                // Center content
                VStack(spacing: 4) {
                    if stressLevel == nil && !isAnimating {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("Awaiting\nData")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if isAnimating {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Analyzing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let level = stressLevel {
                        Text(levelIcon)
                            .font(.system(size: 42))
                        Text(level.rawValue.capitalized)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(levelColor)
                    }
                }
            }
            .scaleEffect(isAnimating ? scale : 1)
            .onAppear {
                if isAnimating {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        scale = 1.05
                    }
                }
            }

            if let confidence = confidence, stressLevel != nil {
                Text("Confidence: \(Int(confidence * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fillAmount: CGFloat {
        guard let level = stressLevel else { return 0 }
        switch level {
        case .low: return 0.3
        case .moderate: return 0.6
        case .high: return 1.0
        case .critical: return 1.0
        }
    }

    private var levelColor: Color {
        guard let level = stressLevel else { return .secondary }
        switch level {
        case .low: return .green
        case .moderate: return .orange
        case .high: return .red
        case .critical: return Color(red: 0.5, green: 0.0, blue: 0.0) // deep dark red
        }
    }

    private var levelIcon: String {
        guard let level = stressLevel else { return "questionmark" }
        switch level {
        case .low: return "🧘"
        case .moderate: return "⚡"
        case .high: return "🔥"
        case .critical: return "🚨"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        StressIndicatorView(stressLevel: .low, confidence: 0.85, isAnimating: false)
        StressIndicatorView(stressLevel: .moderate, confidence: 0.72, isAnimating: false)
        StressIndicatorView(stressLevel: .high, confidence: 0.91, isAnimating: false)
        StressIndicatorView(stressLevel: nil, confidence: nil, isAnimating: true)
    }
    .padding()
}