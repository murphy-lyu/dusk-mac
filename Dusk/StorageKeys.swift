//
//  StorageKeys.swift
//  Dusk
//

enum StorageKeys {
    static let scheduleRules = "scheduleRules"
    static let launchAtLogin  = "launchAtLogin"
    static let hideDockIcon   = "hideDockIcon"
    static let appLanguage    = "appLanguage"
    static let menuBarIcon     = "menuBarIcon"
    static let notifyOnResult  = "notifyOnResult"
}

/// Selectable menu bar glyphs (SF Symbols). Raw value is the symbol name, stored
/// directly in UserDefaults and read by the MenuBarExtra.
enum MenuBarIcon: String, CaseIterable, Identifiable {
    case moon      = "moon.fill"
    case moonZzz   = "moon.zzz.fill"
    case zzz       = "zzz"
    case bolt      = "bolt.fill"
    case leaf      = "leaf.fill"
    case coffee    = "cup.and.saucer.fill"

    static let defaultSymbol = MenuBarIcon.moon.rawValue

    var id: String { rawValue }
    var symbol: String { rawValue }
}
