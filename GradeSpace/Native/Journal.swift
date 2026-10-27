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
    // One school-wide rounding rule: 60 means 4.60 / 3.60 / 2.60 / 1.60.
    var roundingHundredths = 60
    var three: Int { value(for: 3) }
    var four: Int { value(for: 4) }
    var five: Int {
        get { value(for: 5) }
        set { roundingHundredths = newValue - 400 }
    }
    var isValid: Bool { (0...100).contains(roundingHundredths) }
    init(roundingHundredths: Int = 60) { self.roundingHundredths = roundingHundredths }
    init(five: Int) { roundingHundredths = five - 400 }
    func value(for grade: Int) -> Int { grade <= 1 ? 100 : (grade - 1) * 100 + roundingHundredths }

    private enum CodingKeys: String, CodingKey { case roundingHundredths, three, four, five }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let common = try c.decodeIfPresent(Int.self, forKey: .roundingHundredths) {
            roundingHundredths = common
        } else {
            let oldFive = try c.decodeIfPresent(Int.self, forKey: .five) ?? 460
            guard (201...500).contains(oldFive) else {
                throw DecodingError.dataCorruptedError(forKey: .five, in: c, debugDescription: "Неверный порог")
            }
            // Earlier versions allowed unrelated boundaries. Adopt the fraction of
            // their five-boundary as the new common rule; exact integers mean 1.00.
            roundingHundredths = oldFive >= 400 ? oldFive - 400 : (oldFive % 100 == 0 ? 100 : oldFive % 100)
        }
        guard isValid else {
            throw DecodingError.dataCorruptedError(forKey: .roundingHundredths, in: c, debugDescription: "Порог должен быть от 0,00 до 1,00")
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(roundingHundredths, forKey: .roundingHundredths)
        try c.encode(three, forKey: .three)
        try c.encode(four, forKey: .four)
        try c.encode(five, forKey: .five)
    }
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
        if root["thresholds"] == nil { root["thresholds"] = ["roundingHundredths": 60] }
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

    func suggestedFinals(for quarter: Int) -> [String: Int] {
        guard (1...4).contains(quarter) else { return [:] }
        return Dictionary(uniqueKeysWithValues: subjects.compactMap { s in
            guard !s.closedQuarters.contains(quarter),
                  let grade = GradeMath.grade(s.marks(in: quarter), thresholds: thresholds) else { return nil }
            return (s.id, grade)
        })
    }

    mutating func finishQuarter(_ quarter: Int, finals: [String: Int]) throws {
        guard (1...4).contains(quarter) else { throw QuarterError.invalidQuarter }
        let open = subjects.filter { !$0.closedQuarters.contains(quarter) }
        guard !open.isEmpty else { throw QuarterError.noOpenSubjects }
        // Validate every result before changing any subject: all-or-nothing.
        guard Set(finals.keys) == Set(open.map(\.id)), finals.values.allSatisfy({ (1...5).contains($0) }) else {
            throw QuarterError.incompleteFinals
        }
        for i in subjects.indices where !subjects[i].closedQuarters.contains(quarter) {
            subjects[i].quarterFinals[String(quarter)] = finals[subjects[i].id]
            subjects[i].closedQuarters.append(quarter)
            subjects[i].yearFinal = nil
        }
    }
}

enum QuarterError: LocalizedError {
    case invalidQuarter, noOpenSubjects, incompleteFinals
    var errorDescription: String? {
        switch self {
        case .invalidQuarter: return "Выберите четверть от I до IV."
        case .noOpenSubjects: return "Все предметы этой четверти уже завершены."
        case .incompleteFinals: return "Укажите итоговую оценку для каждого незавершённого предмета."
        }
    }
}

struct TrialGrades: Equatable {
    private(set) var quantities = [0, 0, 0, 0, 0]
    var count: Int { quantities.reduce(0, +) }
    func quantity(for grade: Int) -> Int { (1...5).contains(grade) ? quantities[grade - 1] : 0 }
    mutating func setQuantity(_ count: Int, for grade: Int) {
        guard (1...5).contains(grade) else { return }
        quantities[grade - 1] = min(100, max(0, count))
    }
    func previewMarks(in quarter: Int) -> [Mark] {
        (1...5).compactMap { grade in
            let count = quantity(for: grade)
            return count == 0 ? nil : Mark(value: grade, weight: count, ghost: true, quarter: quarter)
        }
    }
    func expandedMarks(in quarter: Int) -> [Mark] {
        (1...5).flatMap { grade in
            (0..<quantity(for: grade)).map { _ in Mark(value: grade, ghost: true, quarter: quarter) }
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
        for grade in stride(from: 5, through: 2, by: -1) {
            if t.sum * 100 >= thresholds.value(for: grade) * t.weight { return grade }
        }
        return 1
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

    static func annual(_ s: Subject, thresholds: Thresholds = Thresholds()) -> Int? {
        guard s.closedQuarters.count == 4 else { return nil }
        if let final = s.yearFinal { return final }
        let finals = (1...4).compactMap { s.quarterFinals[String($0)] }.map { Mark(value: $0) }
        return grade(finals, thresholds: thresholds)
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


