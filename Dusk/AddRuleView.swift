//
//  AddRuleView.swift
//  Dusk
//

import SwiftUI

struct AddRuleView: View {
    @Binding var active: ActiveView
    @ObservedObject private var store = RulesStore.shared

    @State private var selectedType: RuleType = .disconnectWifi
    @State private var hour: Int = 18
    @State private var minute: Int = 30
    @State private var selectedWeekdays: Set<Weekday> = Weekday.workdays
    @State private var noticeEnabled: Bool = false
    @State private var noticeMinutes: Int = 5
    @State private var isOneTime: Bool = false
    @State private var onceYear: Int = Calendar.current.component(.year,  from: Date())
    @State private var onceMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var onceDay: Int = Calendar.current.component(.day,   from: Date())
    @State private var hoveredType: RuleType?
    @State private var hoveredDay: Weekday?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button {
                    active = .main
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                Text(LocalizedStringKey("schedule.add"))
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                // Action
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("schedule.action"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 2) {
                        ForEach(RuleType.selectable, id: \.self) { type in
                            actionRow(type)
                        }
                    }
                }

                // Time
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("schedule.time"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .frame(width: 20, alignment: .leading)
                            .foregroundStyle(.secondary)
                        TimeField(value: $hour, range: 0...23)
                        Text(":")
                            .foregroundStyle(.secondary)
                        TimeField(value: $minute, range: 0...59)
                    }
                    .padding(.leading, 10)   // align with ACTION row icons
                }

                // Days / one-time
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("schedule.days"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Icon + segmented on the same row
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .frame(width: 20, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $isOneTime) {
                            Text(LocalizedStringKey("schedule.recurring")).tag(false)
                            Text(LocalizedStringKey("schedule.once")).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .padding(.leading, 10)

                    // Content row indented to align with picker text (icon 20 + gap 10 = 30pt)
                    // Both branches use the same frame height so the window never resizes.
                    if isOneTime {
                        HStack(spacing: 6) {
                            TimeField(value: $onceYear,  range: 2024...2099, maxDigits: 4, width: 52)
                            Text("/").foregroundStyle(.secondary)
                            TimeField(value: $onceMonth, range: 1...12)
                            Text("/").foregroundStyle(.secondary)
                            TimeField(value: $onceDay,   range: 1...31)
                        }
                        .frame(height: 28)
                        .padding(.leading, 40)
                        let validDate = DateComponents(calendar: .current, year: onceYear, month: onceMonth, day: onceDay).date
                        if validDate == nil {
                            Text("Invalid date")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(.leading, 40)
                        }
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Weekday.allCases) { day in
                                let selected = selectedWeekdays.contains(day)
                                Text(day.localizedShort)
                                    .font(.caption)
                                    .frame(width: 28, height: 24)
                                    .background(
                                        selected ? Color.accentColor
                                        : (hoveredDay == day ? Color.secondary.opacity(0.30)
                                                             : Color.secondary.opacity(0.15)),
                                        in: RoundedRectangle(cornerRadius: 4)
                                    )
                                    .foregroundStyle(selected ? .white : .primary)
                                    .onHover { hoveredDay = $0 ? day : (hoveredDay == day ? nil : hoveredDay) }
                                    .onTapGesture {
                                        if selected { selectedWeekdays.remove(day) }
                                        else        { selectedWeekdays.insert(day) }
                                    }
                            }
                        }
                        .frame(height: 28)
                        .padding(.leading, 40)
                        if selectedWeekdays.isEmpty {
                            Text("Select at least one day")
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(.leading, 40)
                        }
                    }
                }

                // Advance notice — visually separated as it's an optional enhancement.
                if selectedType.supportsAdvanceNotice {
                    Divider()
                        .padding(.vertical, 2)
                    advanceNoticeSection
                }

                if selectedType == .shutdown {
                    Text(LocalizedStringKey("schedule.shutdownNote"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(LocalizedStringKey("schedule.sleepNote"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button {
                    active = .main
                } label: {
                    Text(NSLocalizedString("schedule.cancel", comment: ""))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(width: 100)
                .keyboardShortcut(.cancelAction)
                Button {
                    let notice = noticeEnabled && selectedType.supportsAdvanceNotice
                                 ? noticeMinutes : nil
                    store.add(ScheduleRule(
                        type: selectedType,
                        hour: hour,
                        minute: minute,
                        weekdays: isOneTime ? [] : selectedWeekdays,
                        advanceNoticeMinutes: notice,
                        oneTimeDate: isOneTime ? DateComponents(
                            calendar: .current,
                            year: onceYear, month: onceMonth, day: onceDay
                        ).date : nil
                    ))
                    active = .main
                } label: {
                    Text(NSLocalizedString("schedule.addButton", comment: ""))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(width: 100)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .frame(width: 300)
    }

    private var saveDisabled: Bool {
        if isOneTime {
            guard let date = DateComponents(
                calendar: .current,
                year: onceYear, month: onceMonth, day: onceDay
            ).date else { return true }
            return date < Calendar.current.startOfDay(for: Date())
        }
        return selectedWeekdays.isEmpty
    }

    private func actionRow(_ type: RuleType) -> some View {
        let selected = selectedType == type
        let hovered  = hoveredType == type
        return HStack(spacing: 10) {
            Image(systemName: type.systemImage)
                .font(.system(size: 14))
                .frame(width: 20, alignment: .center)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(type.label)
                .font(.subheadline)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            selected ? Color.accentColor.opacity(0.12)
            : hovered ? Color.primary.opacity(0.06)
            : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredType = isHovering ? type : (hoveredType == type ? nil : hoveredType)
        }
        .onTapGesture { selectedType = type }
    }

    private var advanceNoticeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $noticeEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "bell")
                        .font(.system(size: 14))
                        .frame(width: 20, alignment: .leading)
                        .foregroundStyle(.secondary)
                    Text(LocalizedStringKey("schedule.notice.toggle"))
                        .font(.subheadline)
                    Spacer()   // push the switch to the trailing edge
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            if noticeEnabled {
                Stepper(value: $noticeMinutes, in: 1...60) {
                    Text(String(format: NSLocalizedString(
                            noticeMinutes == 1 ? "schedule.notice.minute" : "schedule.notice.minutes",
                            comment: ""), noticeMinutes))
                        .font(.body)
                        .monospacedDigit()
                }
                .padding(.leading, 30)   // align under the toggle's text
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)   // bell aligns with icons; switch aligns with the ✓ edge
        .animation(.easeInOut(duration: 0.15), value: noticeEnabled)
    }
}
