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
        // loginwindow screenLock is the standard lock mechanism for non-sandboxed apps on macOS 13+.
        // Exit code 0 does not guarantee the screen locked (e.g., Fast User Switching disabled).
        run("/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
            args: ["screenLock"], reply: reply)
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
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            let stderrPipe = Pipe()
            proc.standardError = stderrPipe
            proc.standardOutput = Pipe()  // prevent stdout buffer deadlock
            do {
                try proc.run()
                proc.waitUntilExit()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                if stderrStr.lowercased().contains("not authorized") || stderrStr.contains("-1743") {
                    DispatchQueue.main.async {
                        reply(.failure(.commandFailed("osascript permission denied: Automation access not granted for System Events")))
                    }
                    return
                }
                if proc.terminationStatus == 0 {
                    DispatchQueue.main.async { reply(.success(())) }
                } else {
                    let msg = stderrStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "osascript exited with status \(proc.terminationStatus)"
                        : stderrStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async { reply(.failure(.commandFailed(msg))) }
                }
            } catch {
                DispatchQueue.main.async { reply(.failure(.commandFailed(error.localizedDescription))) }
            }
        }
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
        p.standardError = Pipe()  // prevent stderr buffer deadlock
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
