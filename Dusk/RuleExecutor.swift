//
//  RuleExecutor.swift
//  Dusk
//

import Foundation

final class RuleExecutor {
    static let shared = RuleExecutor()
    private init() {}

    func execute(rule: ScheduleRule, completion: ((Result<Void, HelperError>) -> Void)? = nil) {
        let helper = HelperClient.shared
        let reply: (Result<Void, HelperError>) -> Void = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    NotificationManager.shared.notify(ruleType: rule.type, success: true)
                    ExecutionLog.shared.append(ExecutionRecord(ruleType: rule.type, success: true))
                case .failure(let error):
                    let msg = error.localizedDescription
                    NotificationManager.shared.notify(ruleType: rule.type, success: false, errorMessage: msg)
                    ExecutionLog.shared.append(ExecutionRecord(ruleType: rule.type, success: false, errorMessage: msg))
                }
                completion?(result)
            }
        }
        switch rule.type {
        case .disconnectWifi: helper.disconnectWiFi(reply: reply)
        case .connectWifi:    helper.connectWiFi(reply: reply)
        case .lockScreen:     helper.lockScreen(reply: reply)
        case .systemSleep:    helper.systemSleep(reply: reply)
        case .shutdown:       helper.scheduleShutdown(afterMinutes: 0, reply: reply)
        case .displaySleep:   helper.sleepDisplays(reply: reply)   // deprecated, legacy rules only
        }
    }

    func execute(ruleId: String, completion: (() -> Void)? = nil) {
        guard let uuid = UUID(uuidString: ruleId),
              let rule = RulesStore.shared.rules.first(where: { $0.id == uuid }),
              rule.isEnabled
        else { completion?(); return }

        // User chose "Skip Today" in the advance-notice window
        if AdvanceNoticeManager.shouldSkipToday(ruleId: uuid) {
            AdvanceNoticeManager.clearSkip(for: uuid)
            completion?()
            return
        }

        // Original scheduled job fired while execution was snoozed —
        // the one-time snooze launchd job will fire at the deferred time instead.
        if AdvanceNoticeManager.isSnoozed(ruleId: uuid) {
            completion?()
            return
        }

        // Clear any leftover snooze state and its one-time job before executing
        AdvanceNoticeManager.clearSnooze(for: uuid)
        AdvanceNoticeManager.removeSnoozedJob(ruleId: uuid)

        // A one-time rule is removed BEFORE executing: the action (sleep/shutdown)
        // may suspend this process before any completion callback runs, so we can't
        // rely on cleanup afterward. Removing up-front also unregisters its launchd
        // job, guaranteeing it never fires a second time.
        if rule.isOneTime {
            RulesStore.shared.remove(rule: rule)
        }

        execute(rule: rule) { _ in completion?() }
    }

    /// Called when a `--notice` launch argument is received. Shows the advance-
    /// notice floating window if the rule hasn't already been snoozed or skipped.
    func showNotice(ruleId: String) {
        guard let uuid = UUID(uuidString: ruleId),
              let rule = RulesStore.shared.rules.first(where: { $0.id == uuid }),
              rule.isEnabled,
              let noticeMinutes = rule.advanceNoticeMinutes
        else { return }

        guard !AdvanceNoticeManager.isSnoozed(ruleId: uuid),
              !AdvanceNoticeManager.shouldSkipToday(ruleId: uuid)
        else { return }

        let scheduledDate = Date().addingTimeInterval(Double(noticeMinutes * 60))
        DispatchQueue.main.async {
            AdvanceNoticeWindowController.shared.show(rule: rule, scheduledDate: scheduledDate)
        }
    }
}
