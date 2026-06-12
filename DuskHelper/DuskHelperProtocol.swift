//
//  DuskHelperProtocol.swift
//  DuskHelper
//

import Foundation

@objc protocol DuskHelperProtocol {
    func disconnectWiFi(reply: @escaping (Bool, String?) -> Void)
    func connectWiFi(reply: @escaping (Bool, String?) -> Void)
    func sleepDisplays(reply: @escaping (Bool, String?) -> Void)
    func scheduleShutdown(afterMinutes minutes: Int, reply: @escaping (Bool, String?) -> Void)
    func cancelShutdown(reply: @escaping (Bool, String?) -> Void)
}
