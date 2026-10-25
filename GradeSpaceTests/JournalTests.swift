import XCTest
#if canImport(GradeSpace)
@testable import GradeSpace
#else
@testable import GradeCore
#endif

final class JournalTests: XCTestCase {
    private func marks(_ values: [Int]) -> [Mark] { values.map { Mark(value: $0) } }

    func testExactInclusiveThresholdAndUnroundedClassification() {
        let t = Thresholds()
        XCTAssertEqual(GradeMath.grade(marks([5, 5, 5, 4, 4]), thresholds: t), 5) // exactly 4.60
        let below = [Mark(value: 5, weight: 59), Mark(value: 4, weight: 41)]
        XCTAssertEqual(GradeMath.grade(below, thresholds: t), 4) // 4.59
        // 4.595 rounds to 4.60 for display but must remain a 4.
        let rounded = [Mark(value: 5, weight: 100), Mark(value: 5, weight: 19), Mark(value: 4, weight: 81)]
        XCTAssertEqual(Display.average(rounded), "4,60")
        XCTAssertEqual(GradeMath.grade(rounded, thresholds: t), 4)
    }

    func testUserCanChangeThresholdWithoutChangingMarks() {
        let m = marks([4, 5])
        XCTAssertEqual(GradeMath.grade(m, thresholds: Thresholds(five: 460)), 4)
        XCTAssertEqual(GradeMath.grade(m, thresholds: Thresholds(five: 450)), 5)
        XCTAssertEqual(GradeMath.grade(marks([5, 5, 5, 4]), thresholds: Thresholds(five: 475)), 5)
    }

    func testGhostMarksNeverEnterRealAverageAndRespectQuarter() {
        let s = Subject(name: "Математика", marks: [Mark(value: 4), Mark(value: 5, ghost: true), Mark(value: 2, quarter: 2)])
        XCTAssertEqual(GradeMath.average(s.marks(in: 1)), 4)
        XCTAssertEqual(GradeMath.average(s.marks(in: 1, forecast: true)), 4.5)
        XCTAssertEqual(GradeMath.average(s.marks(in: 2)), 2)
    }

    func testWeightedAverageAndEmptyJournal() {
        XCTAssertNil(GradeMath.average([]))
        XCTAssertNil(GradeMath.grade([], thresholds: Thresholds()))
        XCTAssertEqual(GradeMath.average([Mark(value: 5, weight: 3), Mark(value: 3)]), 4.5)
    }

    func testMinimumFivesIsMinimalAcrossThresholds() {
        for threshold in stride(from: 350, through: 499, by: 1) {
            for value in 1...5 {
                let initial = [Mark(value: value, weight: 3)]
                let count = GradeMath.fivesNeeded(initial, threshold: threshold)!
                let t = GradeMath.totals(initial + Array(repeating: Mark(value: 5), count: count))
                XCTAssertGreaterThanOrEqual(t.sum * 100, threshold * t.weight)
                if count > 0 {
                    let previous = GradeMath.totals(initial + Array(repeating: Mark(value: 5), count: count - 1))
                    XCTAssertLessThan(previous.sum * 100, threshold * previous.weight)
                }
            }
        }
        XCTAssertEqual(GradeMath.fivesNeeded([], threshold: 500), 1)
        XCTAssertNil(GradeMath.fivesNeeded(marks([4, 5]), threshold: 500))
        XCTAssertEqual(GradeMath.fivesNeeded(marks([5]), threshold: 500), 0)
    }

    func testThresholdInputAndOrdering() {
        XCTAssertEqual(Display.parseThreshold("4,60"), 460)
        XCTAssertEqual(Display.parseThreshold("4.75"), 475)
        XCTAssertEqual(Display.parseThreshold("4,6"), 460)
        XCTAssertNil(Display.parseThreshold("4,601"))
        XCTAssertNil(Display.parseThreshold("NaN"))
        XCTAssertFalse(Thresholds(three: 350, four: 350, five: 460).isValid)
        XCTAssertFalse(Thresholds(five: 501).isValid)
    }

    func testLegacyMigrationPreservesQuartersMarksAndTheme() throws {
        let data = Data(#"{"version":1,"theme":"dark","lastQuarter":2,"subjects":[{"id":"subject","name":"Алгебра","color":2,"marks":[{"id":"mark","value":5,"weight":2,"ghost":true,"note":"Контрольная","date":"2026-10-23T12:00:00.000Z","quarter":2}],"quarterFinals":{"1":4},"closedQuarters":[1],"yearFinal":null}]}"#.utf8)
        let journal = try Journal.decode(data)
        XCTAssertEqual(journal.version, 2)
        XCTAssertEqual(journal.theme, "dark")
        XCTAssertEqual(journal.lastQuarter, 2)
        XCTAssertEqual(journal.subjects[0].marks[0].weight, 2)
        XCTAssertTrue(journal.subjects[0].marks[0].ghost)
        XCTAssertEqual(journal.subjects[0].quarterFinals["1"], 4)
        XCTAssertEqual(journal.thresholds.five, 460)
        XCTAssertEqual(try Journal.decode(JSONEncoder().encode(journal)), journal)
    }

    func testInvalidDataRejectedRatherThanSilentlyDiscarded() throws {
        var journal = Journal(subjects: [Subject(name: "Тест", marks: [Mark(value: 5, weight: 0)])])
        XCTAssertThrowsError(try journal.validate())
        journal.subjects[0].marks[0].weight = 1
        journal.subjects.append(journal.subjects[0])
        XCTAssertThrowsError(try journal.validate())
        XCTAssertThrowsError(try Journal.decode(Data("{}".utf8)))
    }

    func testClosedQuarterDoesNotRecalculateWhenThresholdChanges() {
        let s = Subject(name: "Тест", marks: marks([4, 5]), quarterFinals: ["1": 4, "2": 5, "3": 5, "4": 4], closedQuarters: [1, 2, 3, 4])
        XCTAssertEqual(GradeMath.quarterResult(s, quarter: 1, thresholds: Thresholds(five: 450)), 4)
        XCTAssertEqual(GradeMath.annual(s), 5)
    }

    @MainActor
    func testPersistenceAndSafeRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let store = JournalStore(url: url)
        XCTAssertTrue(store.update { $0.subjects.append(Subject(name: "Физика")); $0.thresholds.five = 475 })
        let reloaded = JournalStore(url: url)
        XCTAssertEqual(reloaded.journal, store.journal)
        let broken = Data("broken original".utf8)
        try broken.write(to: url)
        let recovery = JournalStore(url: url)
        XCTAssertTrue(recovery.loadFailed)
        XCTAssertFalse(recovery.update { $0.theme = "dark" })
        XCTAssertEqual(try Data(contentsOf: url), broken)
        XCTAssertTrue(recovery.commit(Journal()))
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("journal.recovered-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: preserved[0]), broken)
    }
}
