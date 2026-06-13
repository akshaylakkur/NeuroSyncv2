//
//  ContentView.swift
//  NeuroSyncv2
//
//  Created by Akshay Lakkur on 6/13/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "house.fill")
                }

            StressHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.indigo)
    }
}

#Preview {
    ContentView()
        .environmentObject(DashboardViewModel())
}