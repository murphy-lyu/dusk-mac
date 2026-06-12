//
//  HistoryView.swift
//  Dusk
//

import SwiftUI

struct HistoryView: View {
    @Binding var active: ActiveView
    @ObservedObject private var log = ExecutionLog.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { active = .main } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                Text(LocalizedStringKey("history.title"))
                    .font(.headline)
                Spacer()
                if !log.records.isEmpty {
                    Button {
                        log.clear()
                    } label: {
                        Text(LocalizedStringKey("history.clear"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if log.records.isEmpty {
                Text(LocalizedStringKey("history.empty"))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(log.records) { record in
                            HistoryRow(record: record)
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 300)
    }
}

private struct HistoryRow: View {
    let record: ExecutionRecord

    private static let timeOnlyFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current)
        return f
    }()
    private static let monthDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    private static func relativeLabel(for date: Date) -> String {
        let cal = Calendar.current
        let time = timeOnlyFmt.string(from: date)
        // `next.today` is a format string ("Today %@") — fill the time into the
        // placeholder rather than concatenating, or the literal %@ leaks through.
        if cal.isDateInToday(date)     { return String(format: NSLocalizedString("next.today", comment: ""), time) }
        if cal.isDateInYesterday(date) { return "\(NSLocalizedString("history.yesterday", comment: "")) \(time)" }
        return "\(monthDayFmt.string(from: date))  \(time)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(record.success ? .green : .red)
                .font(.subheadline)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.ruleType.label)
                    .font(.subheadline)
                    .lineLimit(1)
                if let err = record.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(Self.relativeLabel(for: record.executedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
