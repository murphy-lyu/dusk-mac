//
//  DuskApp.swift
//  Dusk
//

import SwiftUI

/// How this process was started.
enum LaunchMode {
    case normal      // user clicked the app / login item
    case executeRule // launchd fired `--rule <id>`
    case showNotice  // launchd fired `--notice <id>`
}

/// Decided once at startup, never changes.
final class AppState {
    static let shared = AppState()
    let launchMode: LaunchMode
    private init() {
        let args = CommandLine.arguments
        if args.contains("--rule") {
            launchMode = .executeRule
        } else if args.contains("--notice") {
            launchMode = .showNotice
        } else {
            launchMode = .normal
        }
    }
    var isHeadless: Bool { launchMode == .executeRule }
}

@main
struct DuskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(StorageKeys.menuBarIcon) private var menuBarIcon = MenuBarIcon.defaultSymbol

    var body: some Scene {
        // Only show the menu bar extra when running normally.
        // `isInserted` must be a constant — binding it to @Published causes
        // "Publishing from within view updates" infinite-loop warnings.
        MenuBarExtra("Dusk", systemImage: menuBarIcon,
                     isInserted: .constant(AppState.shared.launchMode == .normal)) {
            ContentView()
                .onAppear {
                    let hide = UserDefaults.standard.bool(forKey: StorageKeys.hideDockIcon)
                    NSApp.setActivationPolicy(hide ? .accessory : .regular)
                }
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always subscribe to inter-process notifications so a headless/notice
        // instance can receive forwarded work from the main instance and vice versa.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleRuleNotification(_:)),
            name: .duskExecuteRule, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleNoticeNotification(_:)),
            name: .duskShowNotice, object: nil)

        switch AppState.shared.launchMode {
        case .normal:
            break   // nothing special; the MenuBarExtra body handles setup

        case .executeRule:
            // Completely invisible — no Dock, no menu bar icon, quit when done.
            NSApp.setActivationPolicy(.prohibited)
            handleRuleLaunch()

        case .showNotice:
            // Background process; shows a floating panel only.
            NSApp.setActivationPolicy(.accessory)
            handleNoticeLaunch()
        }
    }

    // MARK: - Rule launch

    private func handleRuleLaunch() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--rule"), idx + 1 < args.count else {
            NSApp.terminate(nil); return
        }
        let ruleId    = args[idx + 1]
        let instances = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")

        if instances.count > 1 {
            // Defer to the already-running main instance, then quit.
            DistributedNotificationCenter.default().postNotificationName(
                .duskExecuteRule, object: ruleId, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
        } else {
            RuleExecutor.shared.execute(ruleId: ruleId) {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Notice launch

    private func handleNoticeLaunch() {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--notice"), idx + 1 < args.count else {
            NSApp.terminate(nil); return
        }
        let ruleId = args[idx + 1]

        // The advance-notice window is owned exclusively by the always-running
        // main app. This helper NEVER paints UI itself — it just signals the main
        // app and quits. The main app dedupes (dismiss before show), so any number
        // of signals collapse to a single window. This is what eliminates the
        // multi-window bug: we no longer rely on an unreliable NSRunningApplication
        // count to decide whether to self-show, and racing helpers can't each open
        // their own window.
        //
        // If no main app is running, the signal goes unheard and no advance window
        // appears — acceptable degradation, since the separate execution job still
        // fires on schedule regardless.
        DistributedNotificationCenter.default().postNotificationName(
            .duskShowNotice, object: ruleId, userInfo: nil, deliverImmediately: true)

        // Give distnoted a moment to hand the notification off before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Notification handlers

    @objc private func handleRuleNotification(_ notification: Notification) {
        guard let ruleId = notification.object as? String else { return }
        // The rule is firing now — close any advance-notice window still on screen.
        AdvanceNoticeWindowController.shared.dismiss()
        RuleExecutor.shared.execute(ruleId: ruleId)
    }

    @objc private func handleNoticeNotification(_ notification: Notification) {
        guard let ruleId = notification.object as? String else { return }
        RuleExecutor.shared.showNotice(ruleId: ruleId)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let duskExecuteRule = Notification.Name("com.murphy.dusk.executeRule")
    static let duskShowNotice  = Notification.Name("com.murphy.dusk.showNotice")
}
