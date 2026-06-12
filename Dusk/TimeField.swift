//
//  TimeField.swift
//  Dusk
//

import SwiftUI

struct TimeField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var maxDigits: Int = 2
    var width: CGFloat = 36

    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var formatString: String { "%0\(maxDigits)d" }

    var body: some View {
        TextField("", text: $text)
            .focused($focused)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: width)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { newValue in
                let filtered = newValue.filter { $0.isASCII && $0.isNumber }
                if filtered != newValue { text = filtered }
                if filtered.count > maxDigits { text = String(filtered.prefix(maxDigits)) }
                if let parsed = Int(text) {
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                }
            }
            .onChange(of: focused) { isFocused in
                if isFocused {
                    text = String(format: formatString, value)
                } else {
                    let parsed = Int(text) ?? value
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                    text = String(format: formatString, value)
                }
            }
            .onAppear {
                text = String(format: formatString, value)
            }
    }
}
