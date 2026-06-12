//
//  LaunchdManager.swift
//  Dusk
//

import Foundation

enum LaunchdManager {
    // These are pure constants/derivations with no mutable state, so they are
    // safe to read from any actor — including `isScheduled`, which runs off the
    // main actor. Marking them `nonisolated` lets that method reach them without
    // inheriting the type's main-actor isolation.
    private nonisolated static let labelPrefix = "com.murphy.dusk.rule."
    private nonisolated static var agentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    // Sync all enabled rules to launchd, remove disabled/deleted ones.
    static func sync(rules: [ScheduleRule]) {
        guard let execPath = Bundle.main.executablePath else { return }
        try? FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)

        // Build the full set of expected labels (execution + optional notice per rule)
        var activeLabels = Set<String>()
        for rule in rules where rule.isEnabled {
            activeLabels.insert(labelPrefix + rule.id.uuidString)
            if rule.advanceNoticeMinutes != nil {
                activeLabels.insert(labelPrefix + rule.id.uuidString + ".notice")
            }
        }

        // Remove stale plists (execution, notice, and snooze jobs)
        let existing = (try? FileManager.default.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil)) ?? []
        for url in existing where url.lastPathComponent.hasPrefix("com.murphy.dusk.rule.") {
            let label = url.deletingPathExtension().lastPathComponent
            // Keep snooze jobs (.snooze suffix) — they are managed by AdvanceNoticeManager
            guard !label.hasSuffix(".snooze") else { continue }
            if !activeLabels.contains(label) {
                unload(plistURL: url)
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Write/reload active rules
        for rule in rules where rule.isEnabled {
            // Execution job
            let execURL = agentsDir.appendingPathComponent("\(labelPrefix)\(rule.id.uuidString).plist")
            if let data = executionPlist(for: rule, execPath: execPath) {
                try? data.write(to: execURL)
                unload(plistURL: execURL)
                load(plistURL: execURL)
            }

            // Notice job (optional)
            let noticeURL = agentsDir.appendingPathComponent("\(labelPrefix)\(rule.id.uuidString).notice.plist")
            if let minutes = rule.advanceNoticeMinutes,
               let data = noticePlist(for: rule, execPath: execPath, noticeMinutes: minutes) {
                try? data.write(to: noticeURL)
                unload(plistURL: noticeURL)
                load(plistURL: noticeURL)
            } else {
                // Remove notice job if advance notice was disabled
                unload(plistURL: noticeURL)
                try? FileManager.default.removeItem(at: noticeURL)
            }
        }
    }

    /// Verify a rule is actually registered with launchd — the plist exists on disk
    /// AND the agent is loaded. Used to give the user confidence the timer is live.
    /// `nonisolated` so it can run off the main actor in a background task.
    nonisolated static func isScheduled(rule: ScheduleRule) -> Bool {
        let label = labelPrefix + rule.id.uuidString
        let plistURL = agentsDir.appendingPathComponent("\(label).plist")
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return false }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list", label]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func remove(rule: ScheduleRule) {
        let execURL   = agentsDir.appendingPathComponent("\(labelPrefix)\(rule.id.uuidString).plist")
        let noticeURL = agentsDir.appendingPathComponent("\(labelPrefix)\(rule.id.uuidString).notice.plist")
        unload(plistURL: execURL);   try? FileManager.default.removeItem(at: execURL)
        unload(plistURL: noticeURL); try? FileManager.default.removeItem(at: noticeURL)
    }

    // MARK: - Private

    private static func executionPlist(for rule: ScheduleRule, execPath: String) -> Data? {
        let intervals: [[String: Any]]
        if let date = rule.oneTimeDate {
            // One-time: a single Month/Day interval on that calendar day. The rule
            // deletes itself after running (RuleExecutor), so the yearly repeat of
            // a Month/Day match never actually fires again.
            let c = Calendar.current.dateComponents([.month, .day], from: date)
            guard let month = c.month, let day = c.day else { return nil }
            intervals = [["Month": month, "Day": day, "Hour": rule.hour, "Minute": rule.minute]]
        } else {
            // launchd weekday: 0=Sun … 6=Sat; our enum: Sun=1 … Sat=7
            intervals = rule.weekdays.map { wd in
                ["Hour": rule.hour, "Minute": rule.minute, "Weekday": wd.rawValue - 1]
            }
        }
        let dict: [String: Any] = [
            "Label":             labelPrefix + rule.id.uuidString,
            "ProgramArguments":  [execPath, "--rule", rule.id.uuidString],
            "StartCalendarInterval": intervals,
            "RunAtLoad": false
        ]
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// Notice job fires `noticeMinutes` before the rule's scheduled time.
    /// Handles midnight wraparound — the notice may land on the previous weekday.
    private static func noticePlist(for rule: ScheduleRule,
                                    execPath: String,
                                    noticeMinutes: Int) -> Data? {
        var intervals: [[String: Any]] = []
        for wd in rule.weekdays {
            let execMins  = rule.hour * 60 + rule.minute
            let noticeMins = execMins - noticeMinutes
            let (h, m, dayShift) = normalizeMinutes(noticeMins)
            // launchd weekday: 0=Sun … 6=Sat; shift back if notice crosses midnight
            let launchdWd = ((wd.rawValue - 1) + dayShift + 7) % 7
            intervals.append(["Hour": h, "Minute": m, "Weekday": launchdWd])
        }
        let dict: [String: Any] = [
            "Label":             labelPrefix + rule.id.uuidString + ".notice",
            "ProgramArguments":  [execPath, "--notice", rule.id.uuidString],
            "StartCalendarInterval": intervals,
            "RunAtLoad": false
        ]
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// Normalises a total-minutes value that may be negative (crosses midnight).
    /// Returns (hour, minute, dayShift) where dayShift is 0 or -1.
    private static func normalizeMinutes(_ total: Int) -> (Int, Int, Int) {
        if total < 0 {
            let wrapped = total + 24 * 60
            return (wrapped / 60, wrapped % 60, -1)
        }
        return (total / 60, total % 60, 0)
    }

    private static func load(plistURL: URL) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["load", plistURL.path]
        try? proc.run()
        proc.waitUntilExit()
    }

    private static func unload(plistURL: URL) {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["unload", plistURL.path]
        try? proc.run()
        proc.waitUntilExit()
    }
}
