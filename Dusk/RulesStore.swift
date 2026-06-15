//
//  RulesStore.swift
//  Dusk
//

import Foundation
import Combine
import SwiftUI

final class RulesStore: ObservableObject {
    static let shared = RulesStore()

    @Published var rules: [ScheduleRule] = [] {
        didSet {
            do {
                let data = try JSONEncoder().encode(rules)
                UserDefaults.standard.set(data, forKey: StorageKeys.scheduleRules)
                persistError = nil
            } catch {
                persistError = error.localizedDescription
                return
            }
            syncLaunchd()
        }
    }

    /// Enabled rules that failed to register with launchd. Published so the UI can
    /// warn the user. Updated only AFTER a sync completes — never races with it.
    @Published private(set) var unscheduledRuleIDs: Set<UUID> = []

    /// Non-nil when the last attempt to persist rules to UserDefaults failed.
    @Published var persistError: String? = nil

    private let syncQueue = DispatchQueue(label: "com.murphy.dusk.launchd-sync", qos: .utility)
    private var pendingSyncWork: DispatchWorkItem?

    var conflicts: [RuleConflict] {
        ConflictDetector.conflicts(in: rules)
    }

    private init() {
        rules = load()
        markMissedAndCleanup()
    }

    // Scans for one-time rules whose scheduled time is already past (Mac was off,
    // launchd never fired, or execution was never confirmed). Logs them as "missed"
    // and removes them so the list stays clean.
    func markMissedAndCleanup() {
        let now = Date()
        let missed = rules.filter { rule in
            guard rule.oneTimeDate != nil else { return false }
            return NextTriggerCalculator.next(for: rule, after: now) == nil
        }
        guard !missed.isEmpty else { return }
        for rule in missed {
            let outcome: ExecutionOutcome = AdvanceNoticeManager.shouldSkipToday(ruleId: rule.id) ? .skipped : .missed
            AdvanceNoticeManager.clearSkip(for: rule.id)
            ExecutionLog.shared.append(ExecutionRecord(ruleType: rule.type, outcome: outcome))
        }
        let missedIDs = Set(missed.map { $0.id })
        // Remove silently without triggering syncLaunchd (launchd jobs will have already
        // expired; AdvanceNoticeManager.cleanupOrphanedPlists() handles plist cleanup).
        guard let data = try? JSONEncoder().encode(rules.filter { !missedIDs.contains($0.id) }) else { return }
        UserDefaults.standard.set(data, forKey: StorageKeys.scheduleRules)
        rules = (try? JSONDecoder().decode([ScheduleRule].self, from: data)) ?? rules
    }

    // MARK: - CRUD

    func add(_ rule: ScheduleRule) {
        guard rules.count < 100 else { return }
        rules.append(rule)
    }

    func remove(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
    }

    func remove(rule: ScheduleRule) {
        rules.removeAll { $0.id == rule.id }
    }

    func update(_ rule: ScheduleRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        rules.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    func toggle(_ rule: ScheduleRule) {
        var copy = rule
        copy.isEnabled.toggle()
        update(copy)
    }

    // MARK: - Persistence

    private func load() -> [ScheduleRule] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.scheduleRules),
              let decoded = try? JSONDecoder().decode([ScheduleRule].self, from: data)
        else { return [] }
        return decoded
    }

    private func syncLaunchd() {
        pendingSyncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let snapshot = self.rules
            LaunchdManager.sync(rules: snapshot)
            var failed = Set<UUID>()
            for rule in snapshot where rule.isEnabled && !LaunchdManager.isScheduled(rule: rule) {
                failed.insert(rule.id)
            }
            DispatchQueue.main.async { self.unscheduledRuleIDs = failed }
        }
        pendingSyncWork = work
        syncQueue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
