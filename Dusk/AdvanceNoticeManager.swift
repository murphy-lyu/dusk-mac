//
//  AdvanceNoticeManager.swift
//  Dusk
//

import Foundation

enum AdvanceNoticeManager {

    private static let snoozePrefix = "com.murphy.dusk.snooze."
    private static let skipPrefix   = "com.murphy.dusk.skip."

    private static var agentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    // MARK: - Skip Today

    static func setSkipToday(ruleId: UUID) {
        let ts = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        UserDefaults.standard.set(ts, forKey: skipPrefix + ruleId.uuidString)
    }

    static func shouldSkipToday(ruleId: UUID) -> Bool {
        let ts = UserDefaults.standard.double(forKey: skipPrefix + ruleId.uuidString)
        guard ts > 0 else { return false }
        return Calendar.current.isDateInToday(Date(timeIntervalSince1970: ts))
    }

    static func clearSkip(for ruleId: UUID) {
        UserDefaults.standard.removeObject(forKey: skipPrefix + ruleId.uuidString)
    }

    // MARK: - Snooze

    static func setSnooze(ruleId: UUID, until date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970,
                                  forKey: snoozePrefix + ruleId.uuidString)
    }

    static func isSnoozed(ruleId: UUID) -> Bool {
        let ts = UserDefaults.standard.double(forKey: snoozePrefix + ruleId.uuidString)
        guard ts > 0 else { return false }
        return Date(timeIntervalSince1970: ts) > Date()
    }

    static func clearSnooze(for ruleId: UUID) {
        UserDefaults.standard.removeObject(forKey: snoozePrefix + ruleId.uuidString)
    }

    // MARK: - One-time snoozed execution job

    /// Registers a one-time launchd job that fires the rule's execution at `date`.
    static func scheduleSnoozedExecution(rule: ScheduleRule, at date: Date) {
        guard let execPath = Bundle.main.executablePath else { return }

        let label    = "com.murphy.dusk.rule.\(rule.id.uuidString).snooze"
        let plistURL = agentsDir.appendingPathComponent("\(label).plist")
        removePlist(at: plistURL)   // clean up any prior snooze job

        let cal   = Calendar.current
        let comps = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        guard let month = comps.month, let day   = comps.day,
              let hour  = comps.hour, let minute = comps.minute else { return }

        let dict: [String: Any] = [
            "Label":             label,
            "ProgramArguments":  [execPath, "--rule", rule.id.uuidString],
            // Month + Day pins to a specific date; the job repeats only once a year
            // which is fine — RuleExecutor removes this plist after execution.
            "StartCalendarInterval": [["Month": month, "Day": day,
                                       "Hour": hour,   "Minute": minute]],
            "RunAtLoad": false
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0) else { return }
        try? data.write(to: plistURL)
        launchctl("load", plistURL.path)
    }

    static func removeSnoozedJob(ruleId: UUID) {
        let label    = "com.murphy.dusk.rule.\(ruleId.uuidString).snooze"
        let plistURL = agentsDir.appendingPathComponent("\(label).plist")
        removePlist(at: plistURL)
    }

    // MARK: - Helpers

    private static func removePlist(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        launchctl("unload", url.path)
        try? FileManager.default.removeItem(at: url)
    }

    private static func launchctl(_ verb: String, _ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = [verb, path]
        try? p.run()
        p.waitUntilExit()
    }
}
