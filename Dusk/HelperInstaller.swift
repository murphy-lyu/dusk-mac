//
//  HelperInstaller.swift
//  Dusk
//

import Foundation
import ServiceManagement

enum HelperStatus {
    case notInstalled
    case installed
    case requiresApproval
}

final class HelperInstaller {
    static let shared = HelperInstaller()
    private let helperBundleID = "com.murphy.dusk.DuskHelper"
    private init() {}

    var status: HelperStatus {
        let service = SMAppService.daemon(plistName: "com.murphy.dusk.DuskHelper.plist")
        switch service.status {
        case .enabled:           return .installed
        case .requiresApproval:  return .requiresApproval
        default:                 return .notInstalled
        }
    }

    func install() throws {
        let service = SMAppService.daemon(plistName: "com.murphy.dusk.DuskHelper.plist")
        try service.register()
    }

    func uninstall() throws {
        let service = SMAppService.daemon(plistName: "com.murphy.dusk.DuskHelper.plist")
        try service.unregister()
    }
}
