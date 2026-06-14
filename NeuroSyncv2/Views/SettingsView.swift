import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsVM = SettingsViewModel()
    @EnvironmentObject var dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - NVIDIA API
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("NVIDIA API Key", text: $settingsVM.apiKey)
                            .textContentType(.none)
                            .autocorrectionDisabled()
                        Text("Used to call Nemotron-3 for stress analysis. Stored securely in the Keychain.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Save Key") {
                        settingsVM.saveAPIKey(settingsVM.apiKey)
                        dashboardVM.saveAPIKey(settingsVM.apiKey)
                    }
                    .disabled(settingsVM.apiKey.isEmpty)

                    if !dashboardVM.nvidiaApiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API key is configured")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Label("NVIDIA NIM", systemImage: "cpu")
                }

                // MARK: - Background Refresh
                Section {
                    Toggle(isOn: Binding(
                        get: { settingsVM.backgroundRefreshEnabled },
                        set: { settingsVM.toggleBackgroundRefresh($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Background Stress Check")
                            Text("Periodically check stress levels in the background.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { dashboardVM.autoLaunchExercise },
                        set: { dashboardVM.setAutoLaunchExercise($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-Start Breathing Exercise")
                            Text("When high or critical stress is detected, automatically launch a guided breathing exercise.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Monitoring", systemImage: "clock.arrow.circlepath")
                }

                // MARK: - Permissions
                Section {
                    HStack {
                        Label("Health Data", systemImage: "heart.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text(settingsVM.healthPermissionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Reminders", systemImage: "bell.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        Text(settingsVM.remindersPermissionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button("Open Health Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.caption)
                } header: {
                    Label("Permissions", systemImage: "hand.raised.fill")
                }

                // MARK: - Data Management
                Section {
                    Button(role: .destructive) {
                        settingsVM.showClearConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Stress History")
                        }
                    }
                    .confirmationDialog(
                        "Are you sure?",
                        isPresented: $settingsVM.showClearConfirmation
                    ) {
                        Button("Clear History", role: .destructive) {
                            settingsVM.clearHistory {
                                dashboardVM.clearHistory()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all stress analysis history. This cannot be undone.")
                    }
                } header: {
                    Label("Data", systemImage: "externaldrive")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Model")
                        Spacer()
                        Text(AppConfig.nvidiaModel)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    Link("NVIDIA NIM Documentation", destination: URL(string: "https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b")!)
                        .font(.caption)
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .alert("API Key Saved", isPresented: $settingsVM.showSavedAlert) {
                Button("OK") {}
            } message: {
                Text("Your NVIDIA API key has been saved securely.")
            }
            .onAppear {
                settingsVM.loadSettings()
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DashboardViewModel())
}