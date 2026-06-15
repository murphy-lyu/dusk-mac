//
//  ExecutionLog.swift
//  Dusk
//

import Foundation
import Combine

enum ExecutionOutcome: String, Codable {
    case success
    case failed
    case skipped  // user tapped "Skip Today" in advance-notice window
    case missed   // scheduled time passed without execution (Mac off, rule expired)
}

struct ExecutionRecord: Codable, Identifiable {
    let id: UUID
    let ruleType: RuleType
    let executedAt: Date
    let outcome: ExecutionOutcome
    let errorMessage: String?

    var success: Bool { outcome == .success }

    init(ruleType: RuleType, outcome: ExecutionOutcome, errorMessage: String? = nil) {
        self.id           = UUID()
        self.ruleType     = ruleType
        self.executedAt   = Date()
        self.outcome      = outcome
        self.errorMessage = errorMessage
    }

    // Backward-compatible decoder: old records had `success: Bool` instead of `outcome`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,    forKey: .id)
        ruleType     = try c.decode(RuleType.self, forKey: .ruleType)
        executedAt   = try c.decode(Date.self,    forKey: .executedAt)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        if let o = try c.decodeIfPresent(ExecutionOutcome.self, forKey: .outcome) {
            outcome = o
        } else {
            let ok = (try? c.decode(Bool.self, forKey: .legacySuccess)) ?? false
            outcome = ok ? .success : .failed
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,           forKey: .id)
        try c.encode(ruleType,     forKey: .ruleType)
        try c.encode(executedAt,   forKey: .executedAt)
        try c.encode(outcome,      forKey: .outcome)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }

    enum CodingKeys: String, CodingKey {
        case id, ruleType, executedAt, outcome, errorMessage
        case legacySuccess = "success"
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
