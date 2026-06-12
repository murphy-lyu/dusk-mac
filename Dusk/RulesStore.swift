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
            persist()
            syncLaunchd()
        }
    }

    /// Enabled rules that failed to register with launchd. Published so the UI can
    /// warn the user. Updated only AFTER a sync completes — never races with it.
    @Published private(set) var unscheduledRuleIDs: Set<UUID> = []

    var conflicts: [RuleConflict] {
        ConflictDetector.conflicts(in: rules)
    }

    private init() {
        rules = load()
    }

    // MARK: - CRUD

    func add(_ rule: ScheduleRule) {
        rules.append(rule)
    }

    func remove(at offsets: IndexSet) {
        let toRemove = offsets.map { rules[$0] }
        rules.remove(atOffsets: offsets)
        toRemove.forEach { LaunchdManager.remove(rule: $0) }
    }

    func remove(rule: ScheduleRule) {
        rules.removeAll { $0.id == rule.id }
        LaunchdManager.remove(rule: rule)
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

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: StorageKeys.scheduleRules)
    }

    private func syncLaunchd() {
        // Snapshot on the main thread, then sync + verify serially on a background
        // queue. Verification runs strictly after sync, so it can't observe a
        // half-registered state and produce false "Not scheduled" warnings.
        let snapshot = rules
        DispatchQueue.global(qos: .utility).async {
            LaunchdManager.sync(rules: snapshot)

            var failed = Set<UUID>()
            for rule in snapshot where rule.isEnabled && !LaunchdManager.isScheduled(rule: rule) {
                failed.insert(rule.id)
            }
            DispatchQueue.main.async {
                self.unscheduledRuleIDs = failed
            }
        }
    }
}
