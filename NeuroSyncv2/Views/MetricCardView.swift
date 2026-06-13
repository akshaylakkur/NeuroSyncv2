import SwiftUI

struct MetricCardView: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let isAvailable: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            if isAvailable {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(unit)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.title3)
                    .foregroundColor(Color.secondary.opacity(0.6))
                Text("No data")
                    .font(.caption2)
                    .foregroundColor(Color.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    HStack {
        MetricCardView(
            title: "Heart Rate",
            value: "72",
            unit: "bpm",
            icon: "heart.fill",
            color: .red,
            isAvailable: true
        )
        MetricCardView(
            title: "HRV",
            value: "42",
            unit: "ms",
            icon: "waveform.path.ecg",
            color: .purple,
            isAvailable: true
        )
    }
    .padding()
}