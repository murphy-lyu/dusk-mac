//
//  NextTriggerCalculator.swift
//  Dusk
//

import Foundation

enum NextTriggerCalculator {
    static func next(for rule: ScheduleRule, after date: Date = Date()) -> Date? {
        guard !rule.weekdays.isEmpty else { return nil }

        let calendar = Calendar.current
        let currentHour   = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)

        for dayOffset in 0...7 {
            guard let candidate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            let weekdayRaw = calendar.component(.weekday, from: candidate)
            guard let weekday = Weekday(rawValue: weekdayRaw),
                  rule.weekdays.contains(weekday)
            else { continue }

            if dayOffset == 0 {
                if rule.hour < currentHour { continue }
                if rule.hour == currentHour && rule.minute <= currentMinute { continue }
            }

            var dc = calendar.dateComponents([.year, .month, .day], from: candidate)
            dc.hour   = rule.hour
            dc.minute = rule.minute
            dc.second = 0
            return calendar.date(from: dc)
        }
        return nil
    }

    static func label(for rule: ScheduleRule) -> String? {
        guard rule.isEnabled else { return nil }
        guard let next = next(for: rule) else { return nil }

        let timeFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "HH:mm"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = timeFormat
        let timeStr = timeFmt.string(from: next)

        let calendar = Calendar.current
        if calendar.isDateInToday(next) {
            return String(format: NSLocalizedString("next.today", comment: ""), timeStr)
        } else if calendar.isDateInTomorrow(next) {
            return String(format: NSLocalizedString("next.tomorrow", comment: ""), timeStr)
        } else {
            // Locale-aware short weekday + system time format
            let dayFmt = DateFormatter()
            dayFmt.locale = .current
            dayFmt.setLocalizedDateFormatFromTemplate("EEE")
            let dayStr = dayFmt.string(from: next)
            return "\(dayStr) \(timeStr)"
        }
    }
}
