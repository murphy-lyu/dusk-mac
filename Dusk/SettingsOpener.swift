//
//  SettingsOpener.swift
//  Dusk
//

import AppKit
import SwiftUI

// MARK: - Toolbar identifiers

private extension NSToolbarItem.Identifier {
    static let general = NSToolbarItem.Identifier("general")
    static let about   = NSToolbarItem.Identifier("about")
}

// MARK: - Window controller

final class SettingsOpener: NSObject, NSToolbarDelegate {
    static let shared = SettingsOpener()

    private var window: NSWindow?
    private var hosting: NSHostingController<AnyView>?

    func open() {
        if window == nil {
            window = makeWindow()
        }
        // Defer one runloop turn so the MenuBarExtra panel finishes dismissing
        // before we take focus — otherwise the two race and the settings window
        // can land behind other apps. Activate the app FIRST, then order the
        // window front; `orderFrontRegardless` is required because an accessory
        // (Dock-hidden) app won't be brought forward by makeKeyAndOrderFront alone.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window?.makeKeyAndOrderFront(nil)
            self.window?.orderFrontRegardless()
        }
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = NSLocalizedString("menu.settings", comment: "")
        win.isReleasedWhenClosed = false

        let toolbar = NSToolbar(identifier: "DuskSettings")
        toolbar.delegate = self
        toolbar.selectedItemIdentifier = .general
        toolbar.displayMode = .iconAndLabel
        win.toolbar = toolbar

        // One hosting controller, never replaced — tab switches only update rootView.
        // This prevents AppKit from auto-resizing the window on contentViewController swap.
        let controller = NSHostingController(rootView: view(for: .general))
        controller.sizingOptions = []
        win.contentViewController = controller
        win.setContentSize(NSSize(width: 420, height: 295))
        hosting = controller

        win.center()
        return win
    }

    private func view(for id: NSToolbarItem.Identifier) -> AnyView {
        switch id {
        case .general:
            return AnyView(GeneralSettingsTab().frame(width: 420).padding(.vertical, 20))
        default:
            return AnyView(AboutTab().frame(width: 420))
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.general, .about]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.general, .about]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.general, .about]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .general:
            item.label = NSLocalizedString("settings.general", comment: "")
            item.image = NSImage(systemSymbolName: "gearshape",
                                 accessibilityDescription: NSLocalizedString("settings.general", comment: ""))
            item.action = #selector(selectGeneral)
            item.target = self
        case .about:
            item.label = NSLocalizedString("settings.about", comment: "")
            item.image = NSImage(systemSymbolName: "info.circle",
                                 accessibilityDescription: NSLocalizedString("settings.about", comment: ""))
            item.action = #selector(selectAbout)
            item.target = self
        default: break
        }
        return item
    }

    @objc private func selectGeneral() {
        window?.toolbar?.selectedItemIdentifier = .general
        hosting?.rootView = view(for: .general)
    }

    @objc private func selectAbout() {
        window?.toolbar?.selectedItemIdentifier = .about
        hosting?.rootView = view(for: .about)
    }
}
