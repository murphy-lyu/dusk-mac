//
//  ConflictDetector.swift
//  Dusk
//

import Foundation

struct RuleConflict: Identifiable {
    let id = UUID()
    let ruleA: ScheduleRule
    let ruleB: ScheduleRule
    let message: String
}

enum ConflictDetector {
    static func conflicts(in rules: [ScheduleRule]) -> [RuleConflict] {
        let enabled = rules.filter { $0.isEnabled }
        var found: [RuleConflict] = []

        for i in 0..<enabled.count {
            for j in (i + 1)..<enabled.count {
                let a = enabled[i]
                let b = enabled[j]
                if let conflict = check(a, b) {
                    found.append(conflict)
                }
            }
        }

        // Check one-time vs one-time conflicts (same date, same time, contradictory action)
        let oneTimeRules = enabled.filter { $0.oneTimeDate != nil }
        let cal = Calendar.current
        for i in 0..<oneTimeRules.count {
            for j in (i + 1)..<oneTimeRules.count {
                let a = oneTimeRules[i], b = oneTimeRules[j]
                guard a.hour == b.hour, a.minute == b.minute,
                      let da = a.oneTimeDate, let db = b.oneTimeDate,
                      cal.isDate(da, inSameDayAs: db)
                else { continue }
                let isContradictory = contradictoryPairs.contains { $0.0 == a.type && $0.1 == b.type }
                guard isContradictory else { continue }
                let msg = "\(a.type.label) and \(b.type.label) conflict at \(a.timeString)"
                found.append(RuleConflict(ruleA: a, ruleB: b, message: msg))
            }
        }

        return found
    }

    private static let contradictoryPairs: [(RuleType, RuleType)] = [
        (.disconnectWifi, .connectWifi),
        (.connectWifi, .disconnectWifi),
    ]

    private static func check(_ a: ScheduleRule, _ b: ScheduleRule) -> RuleConflict? {
        guard a.hour == b.hour,
              a.minute == b.minute,
              !a.weekdays.isDisjoint(with: b.weekdays)
        else { return nil }

        let isContradictory = contradictoryPairs.contains { $0.0 == a.type && $0.1 == b.type }
        guard isContradictory else { return nil }

        let msg = "\(a.type.label) and \(b.type.label) conflict at \(a.timeString)"
        return RuleConflict(ruleA: a, ruleB: b, message: msg)
    }
}
