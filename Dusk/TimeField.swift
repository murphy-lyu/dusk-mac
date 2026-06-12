//
//  TimeField.swift
//  Dusk
//

import SwiftUI

struct TimeField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 36)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { newValue in
                let digits = newValue.filter { $0.isNumber }
                if digits != newValue { text = digits }
                if digits.count > 2 { text = String(digits.prefix(2)) }
                // Keep binding in sync so Save captures current text immediately
                if let parsed = Int(text) {
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                }
            }
            .onChange(of: focused) { isFocused in
                if isFocused {
                    // Show raw number for editing
                    text = "\(value)"
                } else {
                    // Commit: clamp to range, format with leading zero
                    let parsed = Int(text) ?? value
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                    text = String(format: "%02d", value)
                }
            }
            .onAppear {
                text = String(format: "%02d", value)
            }
    }
}
