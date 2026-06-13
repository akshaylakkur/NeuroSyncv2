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
    @StateObject private var socialVM = SocialSentimentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dashboardVM)
                .environmentObject(socialVM)
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
                }
        }
    }
}