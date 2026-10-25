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

    func exportURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("GradeSpace-export", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("GradeSpace.json")
        try JSONEncoder().encode(journal).write(to: output, options: .atomic)
        return output
    }
}
