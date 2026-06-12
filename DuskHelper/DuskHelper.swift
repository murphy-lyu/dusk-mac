//
//  DuskHelper.swift
//  DuskHelper
//

import Foundation

class DuskHelper: NSObject, DuskHelperProtocol {

    // MARK: - Wi-Fi

    func disconnectWiFi(reply: @escaping (Bool, String?) -> Void) {
        guard let iface = wifiInterface() else {
            reply(false, "Wi-Fi interface not found")
            return
        }
        run("/usr/sbin/networksetup", args: ["-setairportpower", iface, "off"], reply: reply)
    }

    func connectWiFi(reply: @escaping (Bool, String?) -> Void) {
        guard let iface = wifiInterface() else {
            reply(false, "Wi-Fi interface not found")
            return
        }
        run("/usr/sbin/networksetup", args: ["-setairportpower", iface, "on"], reply: reply)
    }

    // MARK: - Display

    func sleepDisplays(reply: @escaping (Bool, String?) -> Void) {
        run("/usr/bin/pmset", args: ["displaysleepnow"], reply: reply)
    }

    // MARK: - Shutdown

    func scheduleShutdown(afterMinutes minutes: Int, reply: @escaping (Bool, String?) -> Void) {
        run("/sbin/shutdown", args: ["-h", "+\(minutes)"], reply: reply)
    }

    func cancelShutdown(reply: @escaping (Bool, String?) -> Void) {
        run("/sbin/shutdown", args: ["-c"], reply: reply)
    }

    // MARK: - Wi-Fi interface detection

    private func wifiInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallhardwareports"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.contains("Wi-Fi") || line.contains("AirPort") {
                for j in (i + 1)..<min(i + 4, lines.count) {
                    let deviceLine = lines[j].trimmingCharacters(in: .whitespaces)
                    if deviceLine.hasPrefix("Device:") {
                        return deviceLine
                            .replacingOccurrences(of: "Device:", with: "")
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Private

    private func run(_ path: String, args: [String], reply: @escaping (Bool, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            let errOutput = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            reply(ok, ok ? nil : errOutput)
        } catch {
            reply(false, error.localizedDescription)
        }
    }
}
