//
//  ExecutionLog.swift
//  Dusk
//

import Foundation
import Combine

struct ExecutionRecord: Codable, Identifiable {
    let id: UUID
    let ruleType: RuleType
    let executedAt: Date
    let success: Bool
    let errorMessage: String?

    init(ruleType: RuleType, success: Bool, errorMessage: String? = nil) {
        self.id           = UUID()
        self.ruleType     = ruleType
        self.executedAt   = Date()
        self.success      = success
        self.errorMessage = errorMessage
    }
}

final class ExecutionLog: ObservableObject {
    static let shared = ExecutionLog()

    @Published private(set) var records: [ExecutionRecord] = []

    private let maxCount = 50
    private let storageKey = "executionLog"

    private init() { load() }

    func append(_ record: ExecutionRecord) {
        records.insert(record, at: 0)
        if records.count > maxCount { records = Array(records.prefix(maxCount)) }
        persist()
    }

    func clear() {
        records = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ExecutionRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
