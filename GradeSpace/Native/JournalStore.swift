import Foundation
import Combine

@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var journal = Journal()
    @Published var error: String?
    @Published private(set) var loadFailed = false
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GradeSpace/journal.json")
        load()
    }

    func load() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count <= 10 * 1024 * 1024 else { throw JournalError.invalid }
                journal = try Journal.decode(data)
            }
            loadFailed = false
        } catch {
            loadFailed = true
            self.error = "Не удалось прочитать журнал. Исходный файл сохранён. " + error.localizedDescription
        }
    }

    @discardableResult
    func update(_ edit: (inout Journal) -> Void) -> Bool {
        guard !loadFailed else { return false }
        var next = journal
        edit(&next)
        return commit(next)
    }

    @discardableResult
    func commit(_ next: Journal) -> Bool {
        do {
            try next.validate()
            let data = try JSONEncoder().encode(next)
            guard data.count <= 10 * 1024 * 1024 else { throw JournalError.invalid }
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let old = try? Data(contentsOf: url) {
                // Never destroy an unreadable original when recovering from a failed load.
                let backup = loadFailed ? "journal.recovered-\(UUID().uuidString).json" : "journal.previous.json"
                try old.write(to: folder.appendingPathComponent(backup), options: .atomic)
            }
            try data.write(to: url, options: .atomic)
            journal = next
            loadFailed = false
            return true
        } catch {
            self.error = "Изменения не сохранены. " + error.localizedDescription
            return false
        }
    }

    func subject(_ id: String) -> Subject? { journal.subjects.first { $0.id == id } }

    @discardableResult
    func editSubject(_ id: String, _ edit: (inout Subject) -> Void) -> Bool {
        update { journal in
            if let index = journal.subjects.firstIndex(where: { $0.id == id }) { edit(&journal.subjects[index]) }
        }
    }

    @discardableResult
    func finishQuarter(_ quarter: Int, finals: [String: Int]) -> Bool {
        guard !loadFailed else { return false }
        var next = journal
        do {
            try next.finishQuarter(quarter, finals: finals)
            return commit(next)
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveTrial(_ trial: TrialGrades, subjectID: String, quarter: Int) -> Bool {
        guard !loadFailed, trial.count > 0, (1...4).contains(quarter),
              let subject = subject(subjectID), !subject.closedQuarters.contains(quarter) else {
            error = "Примерку нельзя добавить: проверьте предмет и выбранную четверть."
            return false
        }
        guard subject.marks.count + trial.count <= 20_000 else {
            error = "Слишком много оценок в предмете. Примерка не сохранена."
            return false
        }
        let marks = trial.expandedMarks(in: quarter)
        return editSubject(subjectID) { $0.marks.append(contentsOf: marks) }
    }

    func exportURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Ball-export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("Ball.json")
        try JSONEncoder().encode(journal).write(to: output, options: .atomic)
        return output
    }
}

