import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Error banner
                    if let error = dashboardVM.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                dashboardVM.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.yellow.opacity(0.1))
                        )
                    }

                    // Stress Indicator
                    StressIndicatorView(
                        stressLevel: dashboardVM.latestResult?.stressLevel,
                        confidence: dashboardVM.latestResult?.confidence,
                        isAnimating: dashboardVM.isAnalyzing
                    )

                    // AI Insights
                    LlmSuggestionView(
                        suggestion: dashboardVM.latestResult?.suggestion,
                        reasoning: dashboardVM.latestResult?.reasoning,
                        isLoading: dashboardVM.isAnalyzing,
                        lastUpdated: dashboardVM.lastUpdated,
                        onRefresh: {
                            Task {
                                await dashboardVM.refreshMetrics()
                                await dashboardVM.runStressAnalysis()
                            }
                        }
                    )
                    .padding(.horizontal)

                    // Metrics Grid
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Live Metrics", systemImage: "heart.text.clipboard")
                                .font(.headline)
                            Spacer()
                            if dashboardVM.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }

                        LazyVGrid(columns: columns, spacing: 12) {
                            MetricCardView(
                                title: "Heart Rate",
                                value: dashboardVM.currentMetrics?.heartRate.map { String(format: "%.0f", $0) } ?? "--",
                                unit: "bpm",
                                icon: "heart.fill",
                                color: .red,
                                isAvailable: dashboardVM.currentMetrics?.heartRate != nil
                            )
                            MetricCardView(
                                title: "HRV",
                                value: dashboardVM.currentMetrics?.hrv.map { String(format: "%.0f", $0) } ?? "--",
                                unit: "ms",
                                icon: "waveform.path.ecg",
                                color: .purple,
                                isAvailable: dashboardVM.currentMetrics?.hrv != nil
                            )
                            MetricCardView(
                                title: "Sleep",
                                value: dashboardVM.currentMetrics?.sleepHours.map { String(format: "%.1f", $0) } ?? "--",
                                unit: "hours",
                                icon: "moon.stars.fill",
                                color: .indigo,
                                isAvailable: dashboardVM.currentMetrics?.sleepHours != nil
                            )
                            MetricCardView(
                                title: "Steps",
                                value: dashboardVM.currentMetrics?.steps.map { "\($0)" } ?? "--",
                                unit: "today",
                                icon: "figure.walk",
                                color: .green,
                                isAvailable: dashboardVM.currentMetrics?.steps != nil
                            )
                            MetricCardView(
                                title: "Exercise",
                                value: dashboardVM.currentMetrics?.exerciseMinutes.map { String(format: "%.0f", $0) } ?? "--",
                                unit: "min",
                                icon: "flame.fill",
                                color: .orange,
                                isAvailable: dashboardVM.currentMetrics?.exerciseMinutes != nil
                            )
                            MetricCardView(
                                title: "Mindfulness",
                                value: dashboardVM.currentMetrics?.mindfulMinutes.map { String(format: "%.0f", $0) } ?? "--",
                                unit: "min",
                                icon: "leaf.fill",
                                color: .mint,
                                isAvailable: dashboardVM.currentMetrics?.mindfulMinutes != nil
                            )
                            MetricCardView(
                                title: "Resp. Rate",
                                value: dashboardVM.currentMetrics?.respiratoryRate.map { String(format: "%.1f", $0) } ?? "--",
                                unit: "br/min",
                                icon: "lungs.fill",
                                color: .blue,
                                isAvailable: dashboardVM.currentMetrics?.respiratoryRate != nil
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Quick Action
                    Button(action: {
                        Task {
                            await dashboardVM.refreshMetrics()
                            await dashboardVM.runStressAnalysis()
                        }
                    }) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                            Text(dashboardVM.isAnalyzing ? "Analyzing..." : "Analyze Now")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [.indigo, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(dashboardVM.isAnalyzing)
                    .padding(.horizontal)

                    // Start Breathing Exercise Button — visible only when a plan exists
                    if let plan = dashboardVM.generatedExercisePlan {
                        Button(action: {
                            dashboardVM.generatedExercisePlan = plan
                            dashboardVM.showExerciseSheet = true
                        }) {
                            HStack {
                                Image(systemName: "wind")
                                Text("Start Breathing Exercise")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [.teal, .mint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal)
                    }

                    Color.clear.frame(height: 0)
                        .padding(.bottom, 20)
                }
                .padding(.top)
            }
            // Breathing Exercise Sheet — attached to the ScrollView which always exists
            .fullScreenCover(isPresented: $dashboardVM.showExerciseSheet) {
                if let plan = dashboardVM.generatedExercisePlan {
                    BreathingExerciseView(
                        plan: plan,
                        onDismiss: {
                            dashboardVM.showExerciseSheet = false
                        }
                    )
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("NeuroSync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dashboardVM.isMonitoring ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(dashboardVM.monitoringStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .refreshable {
                await dashboardVM.refreshMetrics()
                await dashboardVM.runStressAnalysis()
            }
            .onAppear {
                dashboardVM.startAutoRefresh()
            }
            .onDisappear {
                dashboardVM.stopAutoRefresh()
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(DashboardViewModel())
}