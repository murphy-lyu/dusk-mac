//
//  NotificationManager.swift
//  Dusk
//

import UserNotifications
import AppKit

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Called when the user turns notifications ON. If they've never been asked,
    /// show the system prompt. If they previously denied, the prompt won't appear
    /// again — send them to System Settings so they can actually re-enable it.
    func requestOrOpenSettings() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            case .denied:
                DispatchQueue.main.async {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            default:
                break
            }
        }
    }

    func notify(ruleType: RuleType, success: Bool, errorMessage: String? = nil) {
        // Respect the user's preference. Absent key = disabled by default;
        // notifications are opt-in (see Settings → Notifications).
        let enabled = UserDefaults.standard.object(forKey: StorageKeys.notifyOnResult) as? Bool ?? false
        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Dusk"
        content.body  = success ? successBody(ruleType) : failBody(ruleType, detail: errorMessage)
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func successBody(_ type: RuleType) -> String {
        switch type {
        case .disconnectWifi: return NSLocalizedString("notif.disconnectWifi.success", comment: "")
        case .connectWifi:    return NSLocalizedString("notif.connectWifi.success",    comment: "")
        case .lockScreen:     return NSLocalizedString("notif.lockScreen.success",     comment: "")
        case .systemSleep:    return NSLocalizedString("notif.systemSleep.success",    comment: "")
        case .displaySleep:   return NSLocalizedString("notif.displaySleep.success",   comment: "")
        case .shutdown:       return NSLocalizedString("notif.shutdown.success",       comment: "")
        }
    }

    private func failBody(_ type: RuleType, detail: String?) -> String {
        let base: String
        switch type {
        case .disconnectWifi: base = NSLocalizedString("notif.disconnectWifi.fail", comment: "")
        case .connectWifi:    base = NSLocalizedString("notif.connectWifi.fail",    comment: "")
        case .lockScreen:     base = NSLocalizedString("notif.lockScreen.fail",     comment: "")
        case .systemSleep:    base = NSLocalizedString("notif.systemSleep.fail",    comment: "")
        case .displaySleep:   base = NSLocalizedString("notif.displaySleep.fail",   comment: "")
        case .shutdown:       base = NSLocalizedString("notif.shutdown.fail",       comment: "")
        }
        if let detail, !detail.isEmpty { return "\(base): \(detail)" }
        return base
    }
}
