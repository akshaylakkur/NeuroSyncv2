//
//  NeuroSyncv2App.swift
//  NeuroSyncv2
//
//  Created by Akshay Lakkur on 6/13/26.
//

import SwiftUI

@main
struct NeuroSyncv2App: App {
    @StateObject private var dashboardVM = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dashboardVM)
                .onAppear {
                    // Pre-seed NVIDIA API key if not already stored
                    if KeychainHelper.load(key: AppConfig.apiKeyAccount) == nil {
                        KeychainHelper.save(key: AppConfig.apiKeyAccount, value: "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")
                        dashboardVM.nvidiaApiKey = "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"
                    }

                    // Register background tasks
                    BackgroundTaskService.shared.registerBackgroundTasks()
                    if UserDefaults.standard.bool(forKey: AppConfig.bgRefreshEnabledKey) {
                        BackgroundTaskService.shared.scheduleBackgroundCheck()
                    }
                    // Request initial authorizations
                    dashboardVM.requestInitialAuthorization()
                    // Check for a Siri-generated exercise plan on cold launch
                    checkForPendingExercise()
                }
                // This fires every time the app becomes active: cold launch,
                // foreground from background, and when Siri finishes and
                // brings the app back to the foreground.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    checkForPendingExercise()
                }
        }
    }

    /// Checks for a pending exercise plan and presents the breathing exercise view.
    /// Polls both the shared App Group store (Siri intent) and standard UserDefaults
    /// (background tasks) because intent runs in a separate process.
    private func checkForPendingExercise() {
        Task {
            for attempt in 0..<15 {
                // Check App Group store (Siri intent, cross-process)
                if let plan = readSharedPlan() {
                    await MainActor.run {
                        dashboardVM.generatedExercisePlan = plan
                        dashboardVM.showExerciseSheet = true
                    }
                    return
                }
                // Check standard UserDefaults (background task, in-process)
                if let data = UserDefaults.standard.data(forKey: AppConfig.lastExercisePlanKey),
                   let plan = try? JSONDecoder().decode(StressExercisePlan.self, from: data) {
                    UserDefaults.standard.removeObject(forKey: AppConfig.lastExercisePlanKey)
                    await MainActor.run {
                        dashboardVM.generatedExercisePlan = plan
                        dashboardVM.showExerciseSheet = true
                    }
                    return
                }
                if attempt < 14 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
    }
}