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

    // UserDefaults key for the pmset wake date Dusk last scheduled.
    private static let wakeDefaultsKey = "com.murphy.dusk.scheduledWakeDate"
    // How many seconds before shutdown to wake the Mac.
    private static let wakeLeadSeconds: Double = 30

    // Cache of plist data last written for each label — used to skip unnecessary reloads.
    private static var plistCache: [String: Data] = [:]

    /// Runs a process with a 5-second timeout. Returns true if it exits 0 within the window.
    @discardableResult
    private nonisolated static func runWithTimeout(_ execURL: URL, args: [String]) -> Bool {
        let proc = Process()
        proc.executableURL = execURL
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch { return false }
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { proc.waitUntilExit(); sema.signal() }
        if sema.wait(timeout: .now() + 5) == .timedOut { proc.terminate(); return false }
        return proc.terminationStatus == 0
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
                plistCache.removeValue(forKey: label)
            }
        }

        // Keep the pmset wake event in sync with the nearest shutdown rule.
        syncShutdownWake(rules: rules)

        // Write/reload active rules
        for rule in rules where rule.isEnabled {
            // Execution job
            let execLabel = labelPrefix + rule.id.uuidString
            let execURL = agentsDir.appendingPathComponent("\(execLabel).plist")
            if let data = executionPlist(for: rule, execPath: execPath) {
                if data != plistCache[execLabel] {
                    try? data.write(to: execURL)
                    unload(plistURL: execURL)
                    load(plistURL: execURL)
                    plistCache[execLabel] = data
                }
            }

            // Notice job (optional)
            let noticeLabel = labelPrefix + rule.id.uuidString + ".notice"
            let noticeURL = agentsDir.appendingPathComponent("\(noticeLabel).plist")
            if let minutes = rule.advanceNoticeMinutes,
               let data = noticePlist(for: rule, execPath: execPath, noticeMinutes: minutes) {
                if data != plistCache[noticeLabel] {
                    try? data.write(to: noticeURL)
                    unload(plistURL: noticeURL)
                    load(plistURL: noticeURL)
                    plistCache[noticeLabel] = data
                }
            } else {
                // Remove notice job if advance notice was disabled
                unload(plistURL: noticeURL)
                try? FileManager.default.removeItem(at: noticeURL)
                plistCache.removeValue(forKey: noticeLabel)
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

        return LaunchdManager.runWithTimeout(
            URL(fileURLWithPath: "/bin/launchctl"),
            args: ["list", label]
        )
    }

    static func remove(rule: ScheduleRule) {
        let execURL   = agentsDir.appendingPathComponent("\(labelPrefix)\(rule.id.uuidString).plist")
        let noticeURL = agentsDir.appendingPathComponent("\(labelPrefix)\(rule.id.uuidString).notice.plist")
        unload(plistURL: execURL);   try? FileManager.default.removeItem(at: execURL)
        unload(plistURL: noticeURL); try? FileManager.default.removeItem(at: noticeURL)
    }

    // MARK: - pmset wake management

    /// Keep a single pmset wake event aligned with the nearest upcoming shutdown rule.
    /// Uses precise cancel-by-date so other apps' scheduled wakes are never disturbed.
    private static func syncShutdownWake(rules: [ScheduleRule]) {
        let now = Date()
        let nextShutdown = rules
            .filter { $0.isEnabled && $0.type == .shutdown }
            .compactMap { nextFireDate(for: $0, after: now) }
            .min()

        let prevWake = UserDefaults.standard.object(forKey: wakeDefaultsKey) as? Date
        let newWake  = nextShutdown.map { $0.addingTimeInterval(-wakeLeadSeconds) }

        // Cancel the previously stored wake when it is no longer the right time.
        // Use a 1-second tolerance to avoid spurious reschedules from float precision.
        let prevMatchesNew = newWake.flatMap { nw in prevWake.map { abs($0.timeIntervalSince(nw)) < 1.0 } } ?? false
        if let prev = prevWake, !prevMatchesNew {
            pmsetCancel(at: prev)
            UserDefaults.standard.removeObject(forKey: wakeDefaultsKey)
        }

        // Schedule the new wake if it is in the future and not already stored.
        let alreadyCorrect = prevWake.map { pv in newWake.map { abs(pv.timeIntervalSince($0)) < 1.0 } ?? false } ?? false
        if let target = newWake, target > now, !alreadyCorrect {
            if pmsetSchedule(at: target) {
                UserDefaults.standard.set(target, forKey: wakeDefaultsKey)
            }
        }
    }

    /// Next fire date for either a one-time or weekly rule, strictly after `date`.
    private static func nextFireDate(for rule: ScheduleRule, after date: Date) -> Date? {
        let calendar = Calendar.current
        if let oneTimeDate = rule.oneTimeDate {
            var dc = calendar.dateComponents([.year, .month, .day], from: oneTimeDate)
            dc.hour = rule.hour; dc.minute = rule.minute; dc.second = 0
            guard let fireDate = calendar.date(from: dc) else { return nil }
            return fireDate > date ? fireDate : nil
        }
        return NextTriggerCalculator.next(for: rule, after: date)
    }

    /// Returns true if the command exited 0.
    @discardableResult
    private static func pmsetSchedule(at date: Date) -> Bool {
        return runWithTimeout(
            URL(fileURLWithPath: "/usr/bin/pmset"),
            args: ["schedule", "wake", pmsetDateString(date)]
        )
    }

    private static func pmsetCancel(at date: Date) {
        runWithTimeout(
            URL(fileURLWithPath: "/usr/bin/pmset"),
            args: ["schedule", "cancel", "wake", pmsetDateString(date)]
        )
    }

    private static func pmsetDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MM/dd/yy HH:mm:ss"
        return fmt.string(from: date)
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

        if let oneTimeDate = rule.oneTimeDate {
            // One-time rule: build exec date from the calendar day of oneTimeDate plus
            // rule.hour/minute — do NOT use oneTimeDate's raw time components.
            let cal = Calendar.current
            var execComps = cal.dateComponents([.year, .month, .day], from: oneTimeDate)
            execComps.hour = rule.hour
            execComps.minute = rule.minute
            execComps.second = 0
            guard let execDate = cal.date(from: execComps) else { return nil }
            let noticeDate = execDate.addingTimeInterval(TimeInterval(-noticeMinutes * 60))
            let noticeComps = cal.dateComponents([.month, .day, .hour, .minute], from: noticeDate)
            guard let month = noticeComps.month, let day = noticeComps.day,
                  let h = noticeComps.hour, let m = noticeComps.minute else { return nil }
            intervals = [["Month": month, "Day": day, "Hour": h, "Minute": m]]
        } else {
            for wd in rule.weekdays {
                let execMins   = rule.hour * 60 + rule.minute
                let noticeMins = execMins - noticeMinutes
                let (h, m, dayShift) = normalizeMinutes(noticeMins)
                // launchd weekday: 0=Sun … 6=Sat; shift back if notice crosses midnight
                let launchdWd = ((wd.rawValue - 1) + dayShift + 7) % 7
                intervals.append(["Hour": h, "Minute": m, "Weekday": launchdWd])
            }
        }

        guard !intervals.isEmpty else { return nil }
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
        let daySize = 24 * 60
        let normalized = ((total % daySize) + daySize) % daySize
        let dayShift = total < 0 ? -1 : 0
        return (normalized / 60, normalized % 60, dayShift)
    }

    private static func load(plistURL: URL) {
        runWithTimeout(
            URL(fileURLWithPath: "/bin/launchctl"),
            args: ["load", plistURL.path]
        )
    }

    private static func unload(plistURL: URL) {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        runWithTimeout(
            URL(fileURLWithPath: "/bin/launchctl"),
            args: ["unload", plistURL.path]
        )
    }
}
