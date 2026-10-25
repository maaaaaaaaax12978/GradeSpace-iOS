import Foundation

struct Mark: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var value: Int
    var weight = 1
    var ghost = false
    var note = ""
    var date = ISO8601DateFormatter().string(from: Date())
    var quarter = 1
}

struct Subject: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var color = 0
    var marks: [Mark] = []
    var quarterFinals: [String: Int] = [:]
    var closedQuarters: [Int] = []
    var yearFinal: Int? = nil

    func marks(in quarter: Int, forecast: Bool = false) -> [Mark] {
        marks.filter { $0.quarter == quarter && (forecast || !$0.ghost) }
    }
}

struct Thresholds: Codable, Equatable {
    // Integer hundredths make 4.60 an exact, inclusive boundary.
    var three = 250
    var four = 350
    var five = 460
    var isValid: Bool { 150 < three && three < four && four < five && five <= 500 }
    func value(for grade: Int) -> Int { grade == 5 ? five : grade == 4 ? four : grade == 3 ? three : 100 }
}

struct Journal: Codable, Equatable {
    var version = 2
    var subjects: [Subject] = []
    var theme = "system"
    var lastQuarter = 1
    var thresholds = Thresholds()
    var haptics = true

    static func decode(_ data: Data) throws -> Journal {
        // Preserve the earlier native wrapper's JSON journal, including all quarters.
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? Int, [1, 2].contains(version),
              var subjects = root["subjects"] as? [[String: Any]] else { throw JournalError.invalid }
        root["version"] = 2
        if root["thresholds"] == nil { root["thresholds"] = ["three": 250, "four": 350, "five": 460] }
        if root["haptics"] == nil { root["haptics"] = true }
        if root["theme"] == nil { root["theme"] = "system" }
        if root["lastQuarter"] == nil { root["lastQuarter"] = 1 }
        for i in subjects.indices {
            if subjects[i]["color"] == nil { subjects[i]["color"] = 0 }
            if subjects[i]["quarterFinals"] == nil { subjects[i]["quarterFinals"] = [String: Int]() }
            if subjects[i]["closedQuarters"] == nil { subjects[i]["closedQuarters"] = [Int]() }
            if var marks = subjects[i]["marks"] as? [[String: Any]] {
                for j in marks.indices where marks[j]["quarter"] == nil { marks[j]["quarter"] = 1 }
                subjects[i]["marks"] = marks
            }
        }
        root["subjects"] = subjects
        let journal = try JSONDecoder().decode(Journal.self, from: JSONSerialization.data(withJSONObject: root))
        try journal.validate()
        return journal
    }

    func validate() throws {
        guard version == 2, subjects.count <= 500, thresholds.isValid,
              ["system", "light", "dark"].contains(theme), (1...4).contains(lastQuarter),
              Set(subjects.map(\.id)).count == subjects.count else { throw JournalError.invalid }
        for s in subjects {
            guard !s.id.isEmpty, !s.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  s.name.count <= 80, (0...5).contains(s.color), s.marks.count <= 20_000,
                  Set(s.marks.map(\.id)).count == s.marks.count,
                  Set(s.closedQuarters).count == s.closedQuarters.count,
                  s.closedQuarters.allSatisfy({ (1...4).contains($0) && s.quarterFinals[String($0)] != nil }),
                  s.quarterFinals.allSatisfy({ ["1", "2", "3", "4"].contains($0.key) && (1...5).contains($0.value) }),
                  s.yearFinal == nil || (s.closedQuarters.count == 4 && (1...5).contains(s.yearFinal!))
            else { throw JournalError.invalid }
            for m in s.marks {
                guard !m.id.isEmpty, (1...5).contains(m.value), (1...100).contains(m.weight),
                      (1...4).contains(m.quarter), m.note.count <= 200,
                      ISO8601DateFormatter().date(from: m.date) != nil || fractionalDate(m.date) != nil
                else { throw JournalError.invalid }
            }
        }
    }
}

private func fractionalDate(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: text)
}

enum JournalError: LocalizedError {
    case invalid
    var errorDescription: String? { "Файл журнала имеет неподдерживаемый формат или содержит неверные данные." }
}

enum GradeMath {
    static func totals(_ marks: [Mark]) -> (sum: Int, weight: Int) {
        marks.reduce(into: (sum: 0, weight: 0)) { result, mark in
            result.sum += mark.value * mark.weight
            result.weight += mark.weight
        }
    }

    static func average(_ marks: [Mark]) -> Double? {
        let t = totals(marks)
        return t.weight == 0 ? nil : Double(t.sum) / Double(t.weight)
    }

    static func grade(_ marks: [Mark], thresholds: Thresholds) -> Int? {
        let t = totals(marks)
        guard t.weight > 0 else { return nil }
        for grade in stride(from: 5, through: 3, by: -1) {
            if t.sum * 100 >= thresholds.value(for: grade) * t.weight { return grade }
        }
        return t.sum * 100 >= 150 * t.weight ? 2 : 1
    }

    static func fivesNeeded(_ marks: [Mark], threshold: Int) -> Int? {
        let t = totals(marks)
        let deficit = threshold * t.weight - 100 * t.sum
        if t.weight > 0 && deficit <= 0 { return 0 }
        guard threshold < 500 else { return t.weight == 0 ? 1 : nil }
        if t.weight == 0 { return 1 }
        return (deficit + (500 - threshold) - 1) / (500 - threshold)
    }

    static func quarterResult(_ s: Subject, quarter: Int, thresholds: Thresholds, forecast: Bool = false) -> Int? {
        if s.closedQuarters.contains(quarter) { return s.quarterFinals[String(quarter)] }
        return grade(s.marks(in: quarter, forecast: forecast), thresholds: thresholds)
    }

    static func annual(_ s: Subject) -> Int? {
        guard s.closedQuarters.count == 4 else { return nil }
        if let final = s.yearFinal { return final }
        let sum = (1...4).compactMap { s.quarterFinals[String($0)] }.reduce(0, +)
        return (sum + 2) / 4
    }
}

enum Display {
    static func average(_ marks: [Mark]) -> String {
        let totals = GradeMath.totals(marks)
        guard totals.weight > 0 else { return "—" }
        // Round half up using integers, including exact cases such as 4.595.
        let hundredths = (totals.sum * 200 + totals.weight) / (totals.weight * 2)
        return threshold(hundredths)
    }
    static func threshold(_ n: Int) -> String { String(format: "%d,%02d", n / 100, n % 100) }
    static func parseThreshold(_ text: String) -> Int? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard value.range(of: #"^[1-5](\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ".")
        let fraction = parts.count == 2 ? String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0) : "00"
        guard let whole = Int(parts[0]), let cents = Int(fraction) else { return nil }
        return whole * 100 + cents
    }
}

