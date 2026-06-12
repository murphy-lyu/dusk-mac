//
//  ScheduleRule.swift
//  Dusk
//

import Foundation

enum RuleType: String, Codable, CaseIterable {
    case disconnectWifi = "disconnectWifi"
    case connectWifi    = "connectWifi"
    case lockScreen     = "lockScreen"
    case systemSleep    = "systemSleep"
    case shutdown       = "shutdown"
    case displaySleep   = "displaySleep"

    /// Types offered when creating/editing a rule, in light→heavy order.
    static let selectable: [RuleType] =
        [.disconnectWifi, .connectWifi, .displaySleep, .lockScreen, .systemSleep, .shutdown]

    var label: String {
        switch self {
        case .disconnectWifi: return NSLocalizedString("rule.disconnectWifi", comment: "")
        case .connectWifi:    return NSLocalizedString("rule.connectWifi",    comment: "")
        case .lockScreen:     return NSLocalizedString("rule.lockScreen",     comment: "")
        case .systemSleep:    return NSLocalizedString("rule.systemSleep",    comment: "")
        case .shutdown:       return NSLocalizedString("rule.shutdown",       comment: "")
        case .displaySleep:   return NSLocalizedString("rule.displaySleep",   comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .disconnectWifi: return "wifi.slash"
        case .connectWifi:    return "wifi"
        case .lockScreen:     return "lock.fill"
        case .systemSleep:    return "moon.zzz.fill"
        case .shutdown:       return "power"
        case .displaySleep:   return "moon"
        }
    }

    /// Advance notice is offered for every action type.
    var supportsAdvanceNotice: Bool { true }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday:    return "Sun"
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        case .saturday:  return "Sat"
        }
    }

    /// Locale-aware very short symbol (e.g. "Mon" / "周一")
    var localizedShort: String {
        // Calendar weekday symbols: index 0 = Sunday
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return symbols[rawValue - 1]
    }

    static var workdays: Set<Weekday> {
        [.monday, .tuesday, .wednesday, .thursday, .friday]
    }
}

struct ScheduleRule: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: RuleType
    var hour: Int
    var minute: Int
    var weekdays: Set<Weekday>
    var isEnabled: Bool = true
    /// Minutes before the scheduled time to show the advance notice window.
    /// `nil` means no advance notice.
    var advanceNoticeMinutes: Int? = nil

    /// When set, this is a one-time rule that fires once on that calendar day
    /// (LaunchdManager schedules a Month/Day interval). `nil` = repeats weekly
    /// on `weekdays`. Optional with a default so existing persisted rules still
    /// decode unchanged.
    var oneTimeDate: Date? = nil

    var isOneTime: Bool { oneTimeDate != nil }

    var schemaVersion: Int = 1

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current)
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
