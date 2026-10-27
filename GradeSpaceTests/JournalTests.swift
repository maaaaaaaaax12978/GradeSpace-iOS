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
        XCTAssertFalse(Thresholds(roundingHundredths: -1).isValid)
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
        XCTAssertEqual(GradeMath.annual(s), 4)
        XCTAssertEqual(GradeMath.annual(s, thresholds: Thresholds(five: 450)), 5)
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

    func testCommonThresholdAppliesToEveryGradeAndYear() {
        let t = Thresholds(five: 460)
        XCTAssertEqual(t.roundingHundredths, 60)
        XCTAssertEqual(t.four, 360)
        XCTAssertEqual(t.three, 260)
        XCTAssertEqual(t.value(for: 2), 160)
        for grade in 2...5 {
            let exact = [Mark(value: grade - 1, weight: 40), Mark(value: grade, weight: 60)]
            let below = [Mark(value: grade - 1, weight: 41), Mark(value: grade, weight: 59)]
            XCTAssertEqual(GradeMath.grade(exact, thresholds: t), grade)
            XCTAssertEqual(GradeMath.grade(below, thresholds: t), grade - 1)
        }
        var changed = t
        changed.five = 475
        XCTAssertEqual(changed.four, 375)
        XCTAssertEqual(changed.three, 275)
        XCTAssertEqual(changed.value(for: 2), 175)
        XCTAssertEqual(Thresholds(five: 400).four, 300)
        XCTAssertEqual(Thresholds(five: 500).four, 400)
    }

    func testOldIndependentThresholdsMigrateToOneCommonRule() throws {
        for (five, expected) in [(460, 60), (475, 75), (400, 0), (500, 100)] {
            let data = Data("{\"three\":250,\"four\":350,\"five\":\(five)}".utf8)
            let t = try JSONDecoder().decode(Thresholds.self, from: data)
            XCTAssertEqual(t.roundingHundredths, expected)
            XCTAssertEqual(t.four, 300 + expected)
            XCTAssertEqual(t.three, 200 + expected)
            XCTAssertEqual(try JSONDecoder().decode(Thresholds.self, from: JSONEncoder().encode(t)), t)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(Thresholds.self, from: Data("{\"roundingHundredths\":101}".utf8)))
    }

    func testWholeQuarterSuggestionsExcludeGhostsAndClosedSubjects() {
        let a = Subject(name: "Алгебра", marks: [Mark(value: 4), Mark(value: 4), Mark(value: 5, weight: 100, ghost: true)])
        let b = Subject(name: "Физика", marks: [Mark(value: 5, ghost: true)])
        let closed = Subject(name: "Химия", marks: [Mark(value: 5)], quarterFinals: ["1": 3], closedQuarters: [1])
        let j = Journal(subjects: [a, b, closed])
        XCTAssertEqual(j.suggestedFinals(for: 1), [a.id: 4])
        XCTAssertTrue(j.suggestedFinals(for: 0).isEmpty)
    }

    func testFinishWholeQuarterSupportsManualEmptySubjectAndPreservesClosedResults() throws {
        let a = Subject(name: "Алгебра", marks: [Mark(value: 4), Mark(value: 5, ghost: true), Mark(value: 3, quarter: 2)])
        let b = Subject(name: "Физкультура")
        let closed = Subject(name: "Музыка", quarterFinals: ["1": 5, "2": 5, "3": 5, "4": 5], closedQuarters: [1, 2, 3, 4], yearFinal: 4)
        var j = Journal(subjects: [a, b, closed])
        try j.finishQuarter(1, finals: [a.id: 4, b.id: 3])
        XCTAssertTrue(j.subjects.allSatisfy { $0.closedQuarters.contains(1) })
        XCTAssertEqual(j.subjects[0].marks, a.marks)
        XCTAssertEqual(j.subjects[0].quarterFinals["1"], 4)
        XCTAssertEqual(j.subjects[1].quarterFinals["1"], 3)
        XCTAssertEqual(j.subjects[2], closed)
        XCTAssertEqual(j.subjects[0].closedQuarters, [1])
        try j.validate()
    }

    func testFinishWholeQuarterRejectsIncompleteResultsAtomically() throws {
        let a = Subject(name: "А", marks: [Mark(value: 4)])
        let b = Subject(name: "Б", marks: [Mark(value: 5)])
        var j = Journal(subjects: [a, b])
        let original = j
        for results in [[a.id: 4], [a.id: 4, b.id: 6], [a.id: 4, b.id: 5, "unknown": 5]] {
            XCTAssertThrowsError(try j.finishQuarter(1, finals: results))
            XCTAssertEqual(j, original)
        }
        XCTAssertThrowsError(try j.finishQuarter(5, finals: [a.id: 4, b.id: 5]))
        XCTAssertEqual(j, original)
        try j.finishQuarter(1, finals: [a.id: 4, b.id: 5])
        let completed = j
        XCTAssertThrowsError(try j.finishQuarter(1, finals: [:]))
        XCTAssertEqual(j, completed)
    }

    func testTrialAggregatesMatchIndividualMarksAndHaveUniqueIDs() {
        var trial = TrialGrades()
        trial.setQuantity(3, for: 5)
        trial.setQuantity(2, for: 3)
        let actual = [Mark(value: 4, weight: 2)]
        let compressed = actual + trial.previewMarks(in: 2)
        let expanded = actual + trial.expandedMarks(in: 2)
        XCTAssertEqual(trial.count, 5)
        XCTAssertEqual(GradeMath.average(compressed), GradeMath.average(expanded))
        XCTAssertEqual(GradeMath.grade(compressed, thresholds: Thresholds()), GradeMath.grade(expanded, thresholds: Thresholds()))
        XCTAssertEqual(GradeMath.fivesNeeded(compressed, threshold: 460), GradeMath.fivesNeeded(expanded, threshold: 460))
        let marks = trial.expandedMarks(in: 2)
        XCTAssertEqual(Set(marks.map(\.id)).count, 5)
        XCTAssertTrue(marks.allSatisfy { $0.ghost && $0.quarter == 2 && $0.weight == 1 })
        trial.setQuantity(1000, for: 1)
        XCTAssertEqual(trial.quantity(for: 1), 100)
        trial.setQuantity(-1, for: 1)
        XCTAssertEqual(trial.quantity(for: 1), 0)
        trial.setQuantity(10, for: 6)
        XCTAssertEqual(trial.count, 5)
    }

    @MainActor
    func testTrialChangesNothingOnDiskUntilExplicitlySaved() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("journal.json")
        let store = JournalStore(url: url)
        let subject = Subject(name: "Физика", marks: [Mark(value: 4)])
        XCTAssertTrue(store.update { $0.subjects = [subject] })
        let before = try Data(contentsOf: url)
        var trial = TrialGrades()
        trial.setQuantity(3, for: 5)
        trial.setQuantity(1, for: 2)
        _ = GradeMath.average(subject.marks + trial.previewMarks(in: 1))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(store.subject(subject.id)?.marks, subject.marks)
        XCTAssertTrue(store.saveTrial(trial, subjectID: subject.id, quarter: 1))
        let saved = try XCTUnwrap(store.subject(subject.id))
        XCTAssertEqual(saved.marks.count, 5)
        XCTAssertEqual(saved.marks.filter(\.ghost).count, 4)
        XCTAssertEqual(GradeMath.average(saved.marks(in: 1)), 4)
        XCTAssertEqual(JournalStore(url: url).journal, store.journal)
        XCTAssertTrue(store.finishQuarter(1, finals: [subject.id: 4]))
        let closed = try Data(contentsOf: url)
        XCTAssertFalse(store.saveTrial(trial, subjectID: subject.id, quarter: 1))
        XCTAssertEqual(try Data(contentsOf: url), closed)
    }

    @MainActor
    func testWholeQuarterIsPersistedTogetherAndFailedAttemptDoesNotWrite() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("journal.json")
        let store = JournalStore(url: url)
        let a = Subject(name: "А", marks: [Mark(value: 4)])
        let b = Subject(name: "Б", marks: [Mark(value: 5)])
        XCTAssertTrue(store.update { $0.subjects = [a, b] })
        let original = try Data(contentsOf: url)
        XCTAssertFalse(store.finishQuarter(1, finals: [a.id: 4]))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(store.finishQuarter(1, finals: [a.id: 4, b.id: 5]))
        let reloaded = JournalStore(url: url)
        XCTAssertTrue(reloaded.journal.subjects.allSatisfy { $0.closedQuarters.contains(1) })
        XCTAssertEqual(reloaded.journal, store.journal)
    }
}

