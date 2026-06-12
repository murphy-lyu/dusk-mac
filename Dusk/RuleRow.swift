//
//  RuleRow.swift
//  Dusk
//

import SwiftUI

struct RuleRow: View {
    let rule: ScheduleRule
    let isExecuting: Bool
    var isUnscheduled: Bool = false
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onTrigger: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @ObservedObject private var store = RulesStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(rule.isEnabled ? .primary : .tertiary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(rule.type.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                Text(weekdaysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if rule.isEnabled && isUnscheduled {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(LocalizedStringKey("row.notScheduled"))
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(NSLocalizedString("row.notScheduled.help", comment: ""))
                } else if let next = NextTriggerCalculator.label(for: rule) {
                    Text(String(format: NSLocalizedString("row.next", comment: ""), next))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isExecuting {
                ProgressView().controlSize(.small).frame(width: 20)
            } else {
                Menu {
                    actionMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(Text("Options"))
            }

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in store.toggle(rule) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .accessibilityLabel(Text(rule.type.label))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            actionMenu
        }
    }

    /// Shared menu used by both the ··· button and the right-click context menu,
    /// so the two stay identical.
    @ViewBuilder
    private var actionMenu: some View {
        Button { onTrigger() } label: {
            Label(LocalizedStringKey("row.triggerNow"), systemImage: "bolt.fill")
        }
        Button { onEdit() } label: {
            Label(LocalizedStringKey("row.editSchedule"), systemImage: "pencil")
        }
        Divider()
        Button { onMoveUp() } label: {
            Label(LocalizedStringKey("row.moveUp"), systemImage: "arrow.up")
        }
        .disabled(!canMoveUp)
        Button { onMoveDown() } label: {
            Label(LocalizedStringKey("row.moveDown"), systemImage: "arrow.down")
        }
        .disabled(!canMoveDown)
        Divider()
        Button(role: .destructive) {
            store.remove(rule: rule)
        } label: {
            Label(LocalizedStringKey("row.delete"), systemImage: "trash")
        }
    }

    private var iconName: String { rule.type.systemImage }

    private var weekdaysText: String {
        if let date = rule.oneTimeDate {
            let dateFmt = DateFormatter()
            dateFmt.locale = .current
            dateFmt.setLocalizedDateFormatFromTemplate("MMMd")
            return "\(dateFmt.string(from: date)) · \(rule.timeString)"
        }
        if rule.weekdays == Weekday.workdays {
            return "\(NSLocalizedString("row.weekdays", comment: "")) · \(rule.timeString)"
        }
        if rule.weekdays.count == 7 {
            return "\(NSLocalizedString("row.everyDay", comment: "")) · \(rule.timeString)"
        }
        let sorted = rule.weekdays.sorted { $0.rawValue < $1.rawValue }
        return sorted.map { $0.localizedShort }.joined(separator: " ") + " · \(rule.timeString)"
    }
}
