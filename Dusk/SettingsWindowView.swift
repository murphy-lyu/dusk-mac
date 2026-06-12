//
//  SettingsWindowView.swift
//  Dusk
//

import SwiftUI
import ServiceManagement

struct SettingsWindowView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("settings.general", systemImage: "gearshape") }

            AboutTab()
                .tabItem { Label("settings.about", systemImage: "info.circle") }
        }
        .frame(width: 380, height: 280)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage(StorageKeys.hideDockIcon) private var hideDockIcon = false
    @AppStorage(StorageKeys.appLanguage) private var appLanguage = "en"
    @AppStorage(StorageKeys.menuBarIcon) private var menuBarIcon = MenuBarIcon.defaultSymbol
    @AppStorage(StorageKeys.notifyOnResult) private var notifyOnResult = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showRestartAlert = false

    private let languages: [(code: String, name: String)] = [
        ("en",      "English"),
        ("zh-Hans", "简体中文"),
        ("ja",      "日本語"),
        ("ko",      "한국어"),
        ("de",      "Deutsch"),
    ]

    var body: some View {
        Form {
            Section(header: Text("settings.section.startup")) {
                Toggle(LocalizedStringKey("settings.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in applyLaunchAtLogin(newValue) }

                Toggle(LocalizedStringKey("settings.hideDock"), isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { newValue in
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                    }
            }

            Section(header: Text("settings.section.notifications"),
                    footer: Text("settings.notifyFooter")) {
                Toggle(LocalizedStringKey("settings.notifyOnResult"), isOn: $notifyOnResult)
                    .onChange(of: notifyOnResult) { newValue in
                        // Ask for permission only when the user actively turns this on —
                        // the moment they clearly want notifications, so the prompt is
                        // least likely to be dismissed and lost.
                        if newValue { NotificationManager.shared.requestOrOpenSettings() }
                    }
            }

            Section(header: Text("settings.section.appearance"),
                    footer: Text("settings.languageFooter")) {
                HStack {
                    Text(LocalizedStringKey("settings.menuBarIcon"))
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(MenuBarIcon.allCases) { icon in
                            let selected = menuBarIcon == icon.symbol
                            Button {
                                menuBarIcon = icon.symbol
                            } label: {
                                Image(systemName: icon.symbol)
                                    .font(.system(size: 13))
                                    .frame(width: 26, height: 24)
                                    .background(
                                        selected ? Color.accentColor.opacity(0.18) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(selected ? Color.accentColor : .clear, lineWidth: 1)
                                    )
                                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Picker(LocalizedStringKey("settings.language"), selection: $appLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appLanguage) { newValue in
                    UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                    showRestartAlert = true
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .alert(
            LocalizedStringKey("settings.restartTitle"),
            isPresented: $showRestartAlert
        ) {
            Button(LocalizedStringKey("settings.restartButton"), role: .destructive) {
                restartApp()
            }
            Button(LocalizedStringKey("schedule.cancel"), role: .cancel) {}
        } message: {
            Text("settings.restartMessage")
        }
    }

    private func applyLaunchAtLogin(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func restartApp() {
        // Relaunch via a detached shell: wait for THIS instance to fully quit,
        // then `open` a fresh one. Avoids two instances racing on the single-
        // instance lock / MenuBarExtra registration. The shell keeps running
        // after we terminate because it's not tied to our run loop.
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"\(bundlePath)\""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script]
        try? proc.run()

        NSApp.terminate(nil)
    }
}

// MARK: - About

struct AboutTab: View {
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)

            Text("Dusk")
                .font(.title2.bold())
            Text("Version \(version)  Build \(build)")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Divider()
                .frame(width: 150)
                .padding(.vertical, 2)

            HStack(spacing: 8) {
                Link("Twitter / X", destination: URL(string: "https://x.com/murphy_latte")!)
                Text("·")
                    .foregroundStyle(.tertiary)
                Link("GitHub", destination: URL(string: "https://github.com/murphy-lyu/dusk-mac")!)
            }
            .font(.caption)

            Text("@Murphy")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
