//
//  EditRuleView.swift
//  Dusk
//

import SwiftUI

struct EditRuleView: View {
    let rule: ScheduleRule
    @Binding var active: ActiveView
    @ObservedObject private var store = RulesStore.shared

    @State private var selectedType: RuleType
    @State private var hour: Int
    @State private var minute: Int
    @State private var selectedWeekdays: Set<Weekday>
    @State private var noticeEnabled: Bool
    @State private var noticeMinutes: Int
    @State private var isOneTime: Bool
    @State private var onceDate: Date
    @State private var hoveredType: RuleType?
    @State private var hoveredDay: Weekday?

    init(rule: ScheduleRule, active: Binding<ActiveView>) {
        self.rule = rule
        self._active = active
        self._selectedType     = State(initialValue: rule.type)
        self._hour             = State(initialValue: rule.hour)
        self._minute           = State(initialValue: rule.minute)
        self._selectedWeekdays = State(initialValue: rule.weekdays)
        self._noticeEnabled    = State(initialValue: rule.advanceNoticeMinutes != nil)
        self._noticeMinutes    = State(initialValue: rule.advanceNoticeMinutes ?? 5)
        self._isOneTime        = State(initialValue: rule.isOneTime)
        self._onceDate         = State(initialValue: rule.oneTimeDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Button { active = .main } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text(LocalizedStringKey("schedule.edit"))
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
                        Text(":").foregroundStyle(.secondary)
                        TimeField(value: $minute, range: 0...59)
                    }
                    .padding(.leading, 10)
                }

                // Repeat: weekly (weekday picker) or one-time (date picker)
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $isOneTime) {
                        Text(LocalizedStringKey("schedule.recurring")).tag(false)
                        Text(LocalizedStringKey("schedule.once")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if isOneTime {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .frame(width: 20, alignment: .leading)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $onceDate,
                                       in: Date()..., displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }
                        .padding(.leading, 10)
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .frame(width: 20, alignment: .leading)
                                .foregroundStyle(.secondary)
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
                        }
                        .padding(.leading, 10)
                    }
                }

                if selectedType.supportsAdvanceNotice {
                    Divider()
                        .padding(.vertical, 2)
                    advanceNoticeSection
                }

                // Sleep caveat: launchd defers to wake.
                Text(LocalizedStringKey("schedule.sleepNote"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    var updated = rule
                    updated.type     = selectedType
                    updated.hour     = hour
                    updated.minute   = minute
                    updated.weekdays = selectedWeekdays
                    updated.advanceNoticeMinutes = noticeEnabled ? noticeMinutes : nil
                    updated.oneTimeDate = isOneTime ? onceDate : nil
                    store.update(updated)
                    active = .main
                } label: {
                    Text(NSLocalizedString("schedule.save", comment: ""))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(width: 100)
                .keyboardShortcut(.defaultAction)
                .disabled(!isOneTime && selectedWeekdays.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .frame(width: 300)
    }

    private func actionRow(_ type: RuleType) -> some View {
        let selected = selectedType == type
        let hovered  = hoveredType == type
        return HStack(spacing: 10) {
            Image(systemName: type.systemImage)
                .font(.system(size: 14))
                .frame(width: 20, alignment: .leading)
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
        .padding(.vertical, 7)
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
                    Spacer()
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
                .padding(.leading, 30)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .animation(.easeInOut(duration: 0.15), value: noticeEnabled)
    }
}
