//
//  AdvanceNoticeWindowController.swift
//  Dusk
//

import AppKit
import SwiftUI
import Combine

// MARK: - Frosted-glass background

/// A `behindWindow` vibrancy layer so the panel reads as frosted glass over the
/// desktop, adapting to light/dark automatically.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = .behindWindow
        v.state        = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
    }
}

// MARK: - View Model

final class AdvanceNoticeViewModel: ObservableObject {
    let rule: ScheduleRule
    let totalSeconds: Int
    @Published var remainingSeconds: Int

    let onSnooze: (Int) -> Void
    let onSkip:   () -> Void
    let onExpire: () -> Void
    let onClose:  () -> Void

    private var timerCancellable: AnyCancellable?
    private var didExpire = false

    init(rule: ScheduleRule,
         scheduledDate: Date,
         onSnooze: @escaping (Int) -> Void,
         onSkip:   @escaping () -> Void,
         onExpire: @escaping () -> Void,
         onClose:  @escaping () -> Void) {
        self.rule     = rule
        self.onSnooze = onSnooze
        self.onSkip   = onSkip
        self.onExpire = onExpire
        self.onClose  = onClose

        let secs              = max(1, Int(scheduledDate.timeIntervalSinceNow))
        self.totalSeconds     = secs
        self.remainingSeconds = secs

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.remainingSeconds > 0 {
                    self.remainingSeconds -= 1
                } else if !self.didExpire {
                    // Countdown hit zero — the separate execution job is now firing.
                    // Dismiss the window so it doesn't linger at 0:00.
                    self.didExpire = true
                    self.onExpire()
                }
            }
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }

    /// Ring colour ramps with urgency: brand colour while there's plenty of time,
    /// orange past the halfway point, red in the final stretch.
    var ringColor: Color {
        if progress > 0.5      { return .accentColor }
        else if progress > 0.2 { return .orange }
        else                   { return .red }
    }

    var timeLabel: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - SwiftUI View

struct AdvanceNoticeView: View {
    @ObservedObject var vm: AdvanceNoticeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Ring countdown + rule info
            HStack(spacing: 14) {
                ringCountdown

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: vm.rule.type.systemImage)
                            .font(.subheadline)
                            .foregroundStyle(vm.ringColor)
                        Text(vm.rule.type.label)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(LocalizedStringKey("notice.autoRunHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Actions — two snooze buttons are primary; "Skip Today" is de-emphasised.
            HStack(spacing: 8) {
                Button(NSLocalizedString("notice.snooze15", comment: "")) { vm.onSnooze(15) }
                Button(NSLocalizedString("notice.snooze30", comment: "")) { vm.onSnooze(30) }
                    .buttonStyle(.bordered)
                Spacer(minLength: 4)
                Button(NSLocalizedString("notice.skipToday", comment: "")) { vm.onSkip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 320)
        // "I've seen it" — close the window without changing anything; the
        // separate execution job still runs at the scheduled time.
        .overlay(alignment: .topTrailing) {
            Button(action: vm.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .help(NSLocalizedString("notice.dismiss", comment: ""))
        }
    }

    private var ringCountdown: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: vm.progress)
                .stroke(vm.ringColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: vm.progress)

            Text(vm.timeLabel)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: 58, height: 58)
    }
}

// MARK: - Window Controller

final class AdvanceNoticeWindowController: NSObject {
    static let shared = AdvanceNoticeWindowController()
    private var panel: NSPanel?
    private var hosting: NSHostingController<AnyView>?
    private var viewModel: AdvanceNoticeViewModel?

    func show(rule: ScheduleRule, scheduledDate: Date) {
        dismiss()

        let vm = AdvanceNoticeViewModel(
            rule: rule,
            scheduledDate: scheduledDate,
            onSnooze: { [weak self] minutes in self?.handleSnooze(rule: rule, minutes: minutes) },
            onSkip:   { [weak self] in self?.handleSkip(rule: rule) },
            onExpire: { [weak self] in self?.dismiss() },
            onClose:  { [weak self] in self?.dismiss() }
        )
        viewModel = vm

        let p = NSPanel(
            contentRect: .zero,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        // Transparent window so the frosted-glass content shows through; the
        // rounded clip on the content gives the card shape, and hasShadow follows
        // the content's alpha (so the shadow is rounded too).
        p.isOpaque             = false
        p.backgroundColor      = .clear
        p.hasShadow            = true
        p.level                = .floating
        p.isFloatingPanel      = true
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = AdvanceNoticeView(vm: vm)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        let controller = NSHostingController(rootView: AnyView(root))
        controller.sizingOptions = []
        p.contentViewController = controller
        p.setContentSize(NSSize(width: 320, height: 132))

        // Top-right of the visible area, with a small inset so the rounded corners
        // and drop shadow of the frosted card aren't clipped by the screen edge.
        if let screen = NSScreen.main {
            let margin: CGFloat = 12
            let vf   = screen.visibleFrame
            let size = p.frame.size
            p.setFrameOrigin(NSPoint(x: vf.maxX - size.width  - margin,
                                     y: vf.maxY - size.height - margin))
        }

        panel   = p
        hosting = controller
        p.orderFrontRegardless()
    }

    func dismiss() {
        panel?.close()
        panel     = nil
        hosting   = nil
        viewModel = nil
        // If this process was launched solely to show the notice window, quit
        // once the panel is gone (user acted, or execution arrived and closed it).
        if AppState.shared.launchMode == .showNotice {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Private actions

    private func handleSnooze(rule: ScheduleRule, minutes: Int) {
        let target = Date().addingTimeInterval(Double(minutes * 60))
        AdvanceNoticeManager.setSnooze(ruleId: rule.id, until: target)
        AdvanceNoticeManager.scheduleSnoozedExecution(rule: rule, at: target)
        dismiss()
    }

    private func handleSkip(rule: ScheduleRule) {
        AdvanceNoticeManager.setSkipToday(ruleId: rule.id)
        dismiss()
    }
}
