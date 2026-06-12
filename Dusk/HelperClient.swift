//
//  HelperClient.swift
//  Dusk
//
//  Runs system commands directly (non-sandboxed app, no root required for
//  networksetup / pmset; shutdown is handled via osascript).
//

import Foundation

enum HelperError: Error, LocalizedError {
    case notConnected
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:            return "Helper is not connected"
        case .commandFailed(let msg):  return msg
        }
    }
}

final class HelperClient {
    static let shared = HelperClient()
    private init() {}

    // MARK: - Public API

    func disconnectWiFi(reply: @escaping (Result<Void, HelperError>) -> Void) {
        guard let iface = wifiInterface() else {
            reply(.failure(.commandFailed("Wi-Fi interface not found")))
            return
        }
        run("/usr/sbin/networksetup", args: ["-setairportpower", iface, "off"], reply: reply)
    }

    func connectWiFi(reply: @escaping (Result<Void, HelperError>) -> Void) {
        guard let iface = wifiInterface() else {
            reply(.failure(.commandFailed("Wi-Fi interface not found")))
            return
        }
        run("/usr/sbin/networksetup", args: ["-setairportpower", iface, "on"], reply: reply)
    }

    func sleepDisplays(reply: @escaping (Result<Void, HelperError>) -> Void) {
        run("/usr/bin/pmset", args: ["displaysleepnow"], reply: reply)
    }

    func lockScreen(reply: @escaping (Result<Void, HelperError>) -> Void) {
        // CGSession -suspend locks to the login window via fast user switching.
        // Runs in the user session, no root needed; this is the standard CLI lock.
        run("/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
            args: ["-suspend"], reply: reply)
    }

    func systemSleep(reply: @escaping (Result<Void, HelperError>) -> Void) {
        run("/usr/bin/pmset", args: ["sleepnow"], reply: reply)
    }

    func scheduleShutdown(afterMinutes minutes: Int, reply: @escaping (Result<Void, HelperError>) -> Void) {
        // osascript doesn't need root and respects the user session
        let delay = minutes * 60
        let script = delay > 0
            ? "delay \(delay)\ntell application \"System Events\" to shut down"
            : "tell application \"System Events\" to shut down"
        run("/usr/bin/osascript", args: ["-e", script], reply: reply)
    }

    // MARK: - Private

    private func wifiInterface() -> String? {
        let out = shell("/usr/sbin/networksetup", args: ["-listallhardwareports"])
        let lines = out.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.contains("Wi-Fi") || line.contains("AirPort") {
                for j in (i + 1)..<min(i + 4, lines.count) {
                    let l = lines[j].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("Device:") {
                        return l.replacingOccurrences(of: "Device:", with: "")
                                .trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return nil
    }

    private func shell(_ path: String, args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func run(_ path: String, args: [String], reply: @escaping (Result<Void, HelperError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let errPipe = Pipe()
            p.standardError = errPipe
            do {
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 {
                    DispatchQueue.main.async { reply(.success(())) }
                } else {
                    let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                    encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                              ?? "Unknown error"
                    DispatchQueue.main.async { reply(.failure(.commandFailed(msg))) }
                }
            } catch {
                DispatchQueue.main.async { reply(.failure(.commandFailed(error.localizedDescription))) }
            }
        }
    }
}
