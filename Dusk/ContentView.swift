//
//  ContentView.swift
//  Dusk
//

import SwiftUI
import Darwin

enum ActiveView: Equatable {
    case main
    case addRule
    case editRule(ScheduleRule)
    case history
}

struct ContentView: View {
    @State private var active: ActiveView = .main

    var body: some View {
        switch active {
        case .main:
            MainView(active: $active)
        case .addRule:
            AddRuleView(active: $active)
        case .editRule(let rule):
            EditRuleView(rule: rule, active: $active)
                .id(rule.id)
        case .history:
            HistoryView(active: $active)
        }
    }
}

struct MainView: View {
    @ObservedObject private var store = RulesStore.shared
    @AppStorage(StorageKeys.menuBarIcon) private var menuBarIcon = MenuBarIcon.defaultSymbol
    @Binding var active: ActiveView
    @State private var executingRuleID: UUID?
    @State private var lastError: String?
    @State private var pendingConfirmRule: ScheduleRule?
    @State private var referenceDate = Date()

    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: menuBarIcon)
                    .foregroundStyle(.secondary)
                Text("Dusk")
                    .font(.headline)
                Spacer()
                Button { active = .addRule } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                Menu {
                    Button(NSLocalizedString("menu.settings", comment: "")) { SettingsOpener.shared.open() }
                    Button(NSLocalizedString("menu.history", comment: "")) { active = .history }
                    Divider()
                    Button(NSLocalizedString("menu.feedback", comment: "")) { sendFeedback() }
                    Divider()
                    Button(NSLocalizedString("menu.quit", comment: "")) { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Conflict banner
            if !store.conflicts.isEmpty {
                conflictBanner
            }

            // Error banner
            if let error = lastError {
                errorBanner(message: error)
            }

            // Rules list
            if store.rules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.rules) { rule in
                            let index = store.rules.firstIndex(where: { $0.id == rule.id }) ?? 0
                            RuleRow(
                                rule: rule,
                                isExecuting: executingRuleID == rule.id,
                                referenceDate: referenceDate,
                                isUnscheduled: store.unscheduledRuleIDs.contains(rule.id),
                                canMoveUp: index > 0,
                                canMoveDown: index < store.rules.count - 1,
                                onEdit: { active = .editRule(rule) },
                                onTrigger: { triggerManually(rule) },
                                onMoveUp: { store.move(fromOffsets: [index], toOffset: index - 1) },
                                onMoveDown: { store.move(fromOffsets: [index], toOffset: index + 2) }
                            )
                            if index < store.rules.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)

                Divider()
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "checkmark.shield")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey("main.backgroundNote"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

        }
        .frame(width: 300)
        .onAppear {
            referenceDate = Date()
            lastError = nil
            RulesStore.shared.markMissedAndCleanup()  // remove expired once-rules on every panel open
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            // Recalculate at minute boundaries, including after wake or a clock change.
            if floor(now.timeIntervalSince1970 / 60) != floor(referenceDate.timeIntervalSince1970 / 60) {
                referenceDate = now
            }
        }
        .onDisappear { pendingConfirmRule = nil } // FIX M-15: clear pending confirm on panel close

            // In-window confirmation for disruptive actions. Using a system
            // confirmationDialog/alert here would spawn a separate key window and make
            // the MenuBarExtra panel auto-dismiss on focus loss — so we present an
            // inline overlay instead.
            if let rule = pendingConfirmRule {
                confirmOverlay(for: rule)
            }
        }
    }

    private func confirmOverlay(for rule: ScheduleRule) -> some View {
        let isShutdown = rule.type == .shutdown
        let icon       = isShutdown ? "power" : "wifi.slash"
        let titleKey   = isShutdown ? "confirm.shutdown.title"   : "confirm.disconnectWifi.title"
        let messageKey = isShutdown ? "confirm.shutdown.message" : "confirm.disconnectWifi.message"
        let confirmKey = isShutdown ? "confirm.shutdown.confirm" : "confirm.disconnectWifi.confirm"

        return ZStack {
            Rectangle()
                .fill(.black.opacity(0.28))
                .onTapGesture { pendingConfirmRule = nil }

            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text(LocalizedStringKey(titleKey))
                    .font(.headline)
                Text(LocalizedStringKey(messageKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(LocalizedStringKey("schedule.cancel")) {
                        pendingConfirmRule = nil
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                    Button(LocalizedStringKey(confirmKey)) {
                        runRule(rule)
                        pendingConfirmRule = nil
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
            .padding(20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.stars")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey("empty.title"))
                .font(.subheadline.weight(.medium))
            Text(LocalizedStringKey("empty.subtitle"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                active = .addRule
            } label: {
                Label(LocalizedStringKey("empty.addButton"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private var conflictBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(store.conflicts.count == 1
                    ? NSLocalizedString("conflict.one", comment: "")
                    : String(format: NSLocalizedString("conflict.many", comment: ""), store.conflicts.count))
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    @ViewBuilder
    private func errorBanner(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
            Button { lastError = nil } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
    }

    private func sendFeedback() {
        let info       = Bundle.main.infoDictionary ?? [:]
        let version    = info["CFBundleShortVersionString"] as? String ?? "–"
        let build      = info["CFBundleVersion"] as? String ?? "–"
        let osv        = ProcessInfo.processInfo.operatingSystemVersion
        let os         = "macOS \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
        let model      = macModel()

        let subject    = NSLocalizedString("feedback.subject", comment: "")
        let body       = """


---
Dusk \(version) (\(build))
\(model) · \(os)
"""
        var components = URLComponents(string: "mailto:murphy.lyu@icloud.com")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body",    value: body)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func macModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    /// Rule types disruptive enough to warrant a confirmation before a manual run:
    /// shutting down (irreversible) and dropping Wi-Fi (cuts the user's connection).
    private func needsConfirmation(_ type: RuleType) -> Bool {
        type == .shutdown || type == .disconnectWifi
    }

    private func triggerManually(_ rule: ScheduleRule) {
        if needsConfirmation(rule.type) {
            pendingConfirmRule = rule
            return
        }
        runRule(rule)
    }

    private func runRule(_ rule: ScheduleRule) {
        executingRuleID = rule.id
        lastError = nil
        RuleExecutor.shared.execute(rule: rule) { result in
            executingRuleID = nil
            if case .failure(let error) = result {
                lastError = error.localizedDescription
            }
        }
    }
}
