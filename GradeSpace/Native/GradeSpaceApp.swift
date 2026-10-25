import SwiftUI
import UniformTypeIdentifiers

@main
struct GradeSpaceApp: App {
    @StateObject private var store = JournalStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(store.journal.theme == "dark" ? .dark : store.journal.theme == "light" ? .light : nil)
                .tint(.indigo)
        }
    }
}

private let subjectColors: [Color] = [.indigo, .teal, .orange, .pink, .blue, .purple]

enum Display {
    static func average(_ marks: [Mark]) -> String {
        guard let n = GradeMath.average(marks) else { return "—" }
        return String(format: "%.2f", n).replacingOccurrences(of: ".", with: ",")
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

struct RootView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var tab = 0
    @State private var recovery = false
    var body: some View {
        Group {
            if store.loadFailed {
                ContentUnavailableView {
                    Label("Журнал не прочитан", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Исходные данные сохранены. Попробуйте прочитать их снова или восстановите JSON-копию в настройках.")
                } actions: {
                    Button("Повторить") { store.load() }
                    Button("Восстановить копию") { recovery = true }
                }
                .sheet(isPresented: $recovery) { NavigationStack { SettingsView() } }
            } else if #available(iOS 26, *) {
                tabs.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                tabs
            }
        }
        .alert("GradeSpace", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Понятно", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            NavigationStack { SubjectsView() }
                .tabItem { Label("Предметы", systemImage: "square.stack.3d.up.fill") }.tag(0)
            NavigationStack { ForecastView() }
                .tabItem { Label("Призрачные", systemImage: "sparkles") }.tag(1)
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }.tag(2)
        }
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
    }
}

struct QuarterPicker: View {
    @EnvironmentObject private var store: JournalStore
    var body: some View {
        Picker("Четверть", selection: Binding(get: { store.journal.lastQuarter }, set: { n in store.update { $0.lastQuarter = n } })) {
            Text("I четверть").tag(1)
            Text("II").tag(2)
            Text("III").tag(3)
            Text("IV").tag(4)
        }.pickerStyle(.segmented)
    }
}

struct SubjectsView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var adding = false
    @State private var editing: Subject?
    @State private var deleting: Subject?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                QuarterPicker()
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Каждая оценка\nменяет картину.").font(.title2.bold())
                        Text("Посмотрите, что будет дальше.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 42)).foregroundStyle(.indigo.gradient)
                        .accessibilityHidden(true)
                }.modifier(Surface())
                if store.journal.subjects.isEmpty {
                    ContentUnavailableView {
                        Label("Первый предмет", systemImage: "books.vertical")
                    } description: {
                        Text("Добавьте предмет и настоящие оценки. Затем попробуйте призрачные — они покажут будущий средний.")
                    } actions: {
                        Button("Добавить предмет", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent)
                    }
                }
                ForEach(store.journal.subjects) { s in
                    NavigationLink { SubjectView(id: s.id) } label: { SubjectCard(subject: s) }
                        .buttonStyle(PressStyle())
                        .contextMenu {
                            Button("Изменить", systemImage: "pencil") { editing = s }
                            Button("Удалить", systemImage: "trash", role: .destructive) { deleting = s }
                        }
                }
            }.padding(20).padding(.bottom, 30)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Предметы")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Добавить предмет", systemImage: "plus") { adding = true } }
        }
        .sheet(isPresented: $adding) { SubjectEditor() }
        .sheet(item: $editing) { SubjectEditor(subject: $0) }
        .confirmationDialog("Удалить предмет и все его оценки?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let s = deleting { store.update { $0.subjects.removeAll { $0.id == s.id } } }
                deleting = nil
            }
        }
    }
}

struct SubjectCard: View {
    @EnvironmentObject private var store: JournalStore
    let subject: Subject
    var body: some View {
        let marks = subject.marks(in: store.journal.lastQuarter)
        let forecast = subject.marks(in: store.journal.lastQuarter, forecast: true)
        let color = subjectColors[subject.color]
        HStack(spacing: 16) {
            Image(systemName: "book.closed.fill").font(.title3)
                .foregroundStyle(color).frame(width: 48, height: 48)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.name).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Text("Оценок: \(marks.count)")
                    if forecast.count > marks.count { Text("· прогноз \(Display.average(forecast))").foregroundStyle(.indigo) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(Display.average(marks)).font(.title2.bold().monospacedDigit()).foregroundStyle(.primary)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }.modifier(Surface())
    }
}

struct SubjectEditor: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let subject: Subject?
    @State private var name: String
    @State private var color: Int
    init(subject: Subject? = nil) {
        self.subject = subject
        _name = State(initialValue: subject?.name ?? "")
        _color = State(initialValue: subject?.color ?? 0)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Например, Математика", text: $name).textInputAutocapitalization(.sentences)
                Picker("Цвет", selection: $color) {
                    ForEach(Array(["Индиго", "Бирюзовый", "Оранжевый", "Розовый", "Синий", "Фиолетовый"].enumerated()), id: \.offset) { i, title in
                        Text(title).tag(i)
                    }
                }
            }.navigationTitle(subject == nil ? "Новый предмет" : "Изменить предмет")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let saved: Bool
                            if let subject {
                                saved = store.editSubject(subject.id) { $0.name = trimmed; $0.color = color }
                            } else {
                                saved = store.update { $0.subjects.append(Subject(name: trimmed, color: color)) }
                            }
                            if saved { dismiss() }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}

struct AverageHero: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let actual: [Mark]
    let forecast: [Mark]
    @State private var floating = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("ВАШ СРЕДНИЙ", systemImage: "chart.bar.fill").font(.caption.bold()).tracking(1.5)
                Spacer()
                Image(systemName: "sparkles").font(.title3)
                    .rotationEffect(.degrees(floating && !reduceMotion ? 12 : -8))
                    .offset(y: floating && !reduceMotion ? -3 : 3)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: floating)
            }.foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(Display.average(actual)).font(.system(size: 58, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Настоящий средний: \(Display.average(actual))")
                if let grade = GradeMath.grade(actual, thresholds: store.journal.thresholds) {
                    Text("Итог \(grade)").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }.foregroundStyle(.white)
            if forecast.contains(where: \.ghost) {
                HStack(alignment: .firstTextBaseline) {
                    Text("С призрачными").font(.subheadline)
                    Spacer()
                    Text(Display.average(forecast)).font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
                }.foregroundStyle(.white)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Примерьте будущие оценки ниже").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.39, green: 0.34, blue: 0.95), Color(red: 0.25, green: 0.25, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 32))
            .onAppear { floating = !reduceMotion }
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: forecast)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.82), value: actual)
    }
}

struct SubjectView: View {
    @EnvironmentObject private var store: JournalStore
    let id: String
    @State private var closing = false
    @State private var final = 5
    @State private var editor = false
    var body: some View {
        Group {
            if let s = store.subject(id) {
                ScrollView {
                    VStack(spacing: 20) {
                        QuarterPicker()
                        AverageHero(actual: s.marks(in: store.journal.lastQuarter), forecast: s.marks(in: store.journal.lastQuarter, forecast: true))
                        if s.closedQuarters.contains(store.journal.lastQuarter) {
                            closedCard(s)
                        } else {
                            MarkSection(subjectID: id, ghost: false)
                            MarkSection(subjectID: id, ghost: true)
                            Button("Завершить четверть", systemImage: "checkmark.seal") {
                                final = GradeMath.grade(s.marks(in: store.journal.lastQuarter), thresholds: store.journal.thresholds) ?? 5
                                closing = true
                            }.buttonStyle(.bordered).disabled(s.marks(in: store.journal.lastQuarter).isEmpty)
                        }
                        annualCard(s)
                        Text("Средний показан с округлением до сотых. Итог определяется по точному среднему и порогам школы.")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(20).padding(.bottom, 30)
                }.background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle(s.name).navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Изменить предмет", systemImage: "pencil") { editor = true } }
                    .sheet(isPresented: $editor) { SubjectEditor(subject: s) }
                    .sheet(isPresented: $closing) { closeSheet(s) }
            } else { ContentUnavailableView("Предмет удалён", systemImage: "book.closed") }
        }
    }

    private func closedCard(_ s: Subject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Четверть завершена: \(s.quarterFinals[String(store.journal.lastQuarter)] ?? 0)", systemImage: "checkmark.seal.fill").font(.headline)
            Text("Настоящих оценок: \(s.marks(in: store.journal.lastQuarter).count). Призрачные оценки не входят в итог.").font(.subheadline).foregroundStyle(.secondary)
            Button("Открыть четверть снова") {
                let q = store.journal.lastQuarter
                store.editSubject(id) { $0.closedQuarters.removeAll { $0 == q }; $0.quarterFinals.removeValue(forKey: String(q)); $0.yearFinal = nil }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(Surface())
    }

    private func annualCard(_ s: Subject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Учебный год", systemImage: "calendar").font(.headline); Spacer(); Text(GradeMath.annual(s).map(String.init) ?? "—").font(.title2.bold()) }
            HStack {
                ForEach(1...4, id: \.self) { q in
                    VStack(spacing: 7) {
                        Text(["I", "II", "III", "IV"][q - 1]).font(.caption).foregroundStyle(.secondary)
                        Text(s.closedQuarters.contains(q) ? String(s.quarterFinals[String(q)] ?? 0) : "—").font(.headline)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Годовая — округлённое среднее итогов четырёх завершённых четвертей.").font(.caption).foregroundStyle(.secondary)
        }.modifier(Surface())
    }

    private func closeSheet(_ s: Subject) -> some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Итоговая оценка", selection: $final) { ForEach(1...5, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.segmented)
                } footer: { Text("Предложен итог по настоящим оценкам и порогам школы. Вы можете указать оценку, которую выставил учитель.") }
            }.navigationTitle("Завершить четверть")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { closing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Завершить") {
                            let q = store.journal.lastQuarter
                            if store.editSubject(id, { $0.quarterFinals[String(q)] = final; if !$0.closedQuarters.contains(q) { $0.closedQuarters.append(q) }; $0.yearFinal = nil }) { closing = false }
                        }
                    }
                }
        }.presentationDetents([.medium])
    }
}

struct MarkSection: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let subjectID: String
    let ghost: Bool
    @State private var selected: Mark?
    @State private var adding = false
    @State private var clear = false
    @State private var promote = false
    @State private var feedback = 0
    var body: some View {
        if let s = store.subject(subjectID) {
            let q = store.journal.lastQuarter
            let marks = s.marks.filter { $0.quarter == q && $0.ghost == ghost }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(ghost ? "Призрачные оценки" : "Настоящие оценки", systemImage: ghost ? "sparkles" : "checkmark.circle.fill").font(.headline)
                    Spacer(minLength: 0)
                    if !marks.isEmpty {
                        Menu {
                            if ghost { Button("Сделать настоящими", systemImage: "checkmark.circle") { promote = true } }
                            Button("Очистить", systemImage: "trash", role: .destructive) { clear = true }
                        } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }.accessibilityLabel("Действия с оценками")
                    }
                }
                if ghost { Text("Что будет, если получить…").font(.subheadline).foregroundStyle(.secondary) }
                if marks.isEmpty {
                    Text(ghost ? "Добавьте оценки для прогноза. Настоящий средний останется прежним." : "Здесь пока пусто. Нажмите оценку ниже, чтобы добавить её.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                        ForEach(marks) { mark in
                            Button { selected = mark } label: {
                                VStack(spacing: 2) {
                                    Text(String(mark.value)).font(.system(.title3, design: .rounded, weight: .bold))
                                    if mark.weight > 1 { Text("×\(mark.weight)").font(.caption2) }
                                }.frame(maxWidth: .infinity, minHeight: 48)
                                    .foregroundStyle(ghost ? Color.indigo : .primary)
                                    .background((ghost ? Color.indigo : Color.primary).opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(ghost ? Color.indigo.opacity(0.45) : .clear, style: StrokeStyle(lineWidth: 1, dash: ghost ? [4, 3] : [])))
                            }.buttonStyle(PressStyle())
                                .accessibilityLabel("\(ghost ? "Призрачная оценка" : "Оценка") \(mark.value), вес \(mark.weight). \(mark.note). Изменить")
                                .transition(.scale(scale: 0.65).combined(with: .opacity))
                        }
                    }
                }
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            perform {
                                if store.editSubject(subjectID, { $0.marks.append(Mark(value: value, ghost: ghost, quarter: q)) }) { feedback += 1 }
                            }
                        } label: {
                            Text(String(value)).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 48)
                                .background(ghost ? Color.indigo.opacity(0.12) : Color.indigo, in: RoundedRectangle(cornerRadius: 15))
                                .foregroundStyle(ghost ? Color.indigo : .white)
                        }.buttonStyle(PressStyle()).accessibilityLabel("Добавить \(ghost ? "призрачную " : "")оценку \(value)")
                    }
                }.disabled(s.marks.count >= 20_000)
                Button("Оценка с весом и заметкой", systemImage: "plus.circle") { adding = true }.font(.subheadline)
                    .disabled(s.marks.count >= 20_000)
                if ghost {
                    let needed = GradeMath.fivesNeeded(s.marks(in: q, forecast: true), threshold: store.journal.thresholds.five)
                    Label(needed.map { $0 == 0 ? "Пятёрка уже в прогнозе" : "До пятёрки: ещё \($0) оценок «5» с весом 1" } ?? "Порог 5,00: достичь его новыми оценками уже нельзя", systemImage: "scope")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(Surface())
                .sensoryFeedback(.impact(weight: .light), trigger: feedback) { _, _ in store.journal.haptics }
                .sheet(item: $selected) { MarkEditor(subjectID: subjectID, ghost: ghost, existing: $0) }
                .sheet(isPresented: $adding) { MarkEditor(subjectID: subjectID, ghost: ghost) }
                .confirmationDialog("Удалить \(ghost ? "призрачные" : "настоящие") оценки этой четверти?", isPresented: $clear, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) { perform { _ = store.editSubject(subjectID) { $0.marks.removeAll { $0.quarter == q && $0.ghost == ghost } } } }
                }
                .confirmationDialog("Внести все призрачные оценки этой четверти в настоящий журнал?", isPresented: $promote, titleVisibility: .visible) {
                    Button("Сделать настоящими") {
                        perform { _ = store.editSubject(subjectID) { s in for i in s.marks.indices where s.marks[i].quarter == q { s.marks[i].ghost = false } } }
                    }
                }
        }
    }
    private func perform(_ edit: () -> Void) { withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75), edit) }
}

struct MarkEditor: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let subjectID: String
    let ghost: Bool
    let existing: Mark?
    @State private var value: Int
    @State private var weight: Int
    @State private var note: String
    @State private var deleting = false
    init(subjectID: String, ghost: Bool, existing: Mark? = nil) {
        self.subjectID = subjectID; self.ghost = ghost; self.existing = existing
        _value = State(initialValue: existing?.value ?? 5)
        _weight = State(initialValue: existing?.weight ?? 1)
        _note = State(initialValue: existing?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Оценка", selection: $value) { ForEach(1...5, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.segmented)
                Stepper("Вес: \(weight)", value: $weight, in: 1...100)
                TextField("Заметка", text: $note, axis: .vertical).lineLimit(2...4)
                if existing != nil { Button("Удалить оценку", role: .destructive) { deleting = true } }
            }.navigationTitle(ghost ? "Призрачная оценка" : "Оценка")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") {
                            let q = store.journal.lastQuarter
                            if store.editSubject(subjectID, { s in
                                guard !s.closedQuarters.contains(existing?.quarter ?? q) else { return }
                                if let existing, let i = s.marks.firstIndex(where: { $0.id == existing.id }) {
                                    s.marks[i].value = value; s.marks[i].weight = weight; s.marks[i].note = note
                                } else if s.marks.count < 20_000 {
                                    s.marks.append(Mark(value: value, weight: weight, ghost: ghost, note: note, quarter: q))
                                }
                            }) { dismiss() }
                        }.disabled(note.count > 200)
                    }
                }
                .confirmationDialog("Удалить оценку?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) {
                        if let existing, store.editSubject(subjectID, { $0.marks.removeAll { $0.id == existing.id } }) { dismiss() }
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}

struct ForecastView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var selected: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                QuarterPicker()
                if store.journal.subjects.isEmpty {
                    ContentUnavailableView("Добавьте предмет", systemImage: "sparkles", description: Text("Предметы и настоящие оценки добавляются на первой вкладке."))
                } else {
                    let id = selected.flatMap { store.subject($0)?.id } ?? store.journal.subjects[0].id
                    Picker("Предмет", selection: Binding(get: { id }, set: { selected = $0 })) {
                        ForEach(store.journal.subjects) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).modifier(Surface())
                    if let s = store.subject(id) {
                        AverageHero(actual: s.marks(in: store.journal.lastQuarter), forecast: s.marks(in: store.journal.lastQuarter, forecast: true))
                        if s.closedQuarters.contains(store.journal.lastQuarter) {
                            ContentUnavailableView("Четверть завершена", systemImage: "lock.fill", description: Text("Выберите другую четверть или откройте эту снова в предмете."))
                        } else { MarkSection(subjectID: id, ghost: true).id(id) }
                    }
                    Text("Настоящий средний не меняется от призрачных оценок. Каждый предмет хранит свой сценарий.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20).padding(.bottom, 30)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Что, если…")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var thresholds = false
    @State private var importing = false
    @State private var pending: Journal?
    @State private var export: URL?
    @State private var sharing = false
    var body: some View {
        Form {
            Section("Оформление") {
                Picker("Тема", selection: Binding(get: { store.journal.theme }, set: { theme in store.update { $0.theme = theme } })) {
                    Text("Системная").tag("system"); Text("Светлая").tag("light"); Text("Тёмная").tag("dark")
                }
                Toggle("Тактильный отклик", isOn: Binding(get: { store.journal.haptics }, set: { n in store.update { $0.haptics = n } }))
            }.disabled(store.loadFailed)
            Section {
                ForEach([5, 4, 3], id: \.self) { grade in
                    HStack { Text("Оценка \(grade)"); Spacer(); Text("от \(Display.threshold(store.journal.thresholds.value(for: grade)))").foregroundStyle(.secondary).monospacedDigit() }
                }
                Button("Изменить пороги") { thresholds = true }
            } header: { Text("Правила школы") } footer: {
                Text("Порог включается: при среднем ровно 4,60 и пороге 4,60 получится 5. Все оценки имеют вес 1, если вы не указали другой. Завершённые четверти сохраняют зафиксированный итог.")
            }.disabled(store.loadFailed)
            Section("Резервная копия") {
                Button("Сохранить в Файлы", systemImage: "square.and.arrow.up") {
                    do { export = try store.exportURL(); sharing = true }
                    catch { store.error = error.localizedDescription }
                }.disabled(store.loadFailed)
                Button("Восстановить JSON-копию", systemImage: "square.and.arrow.down") { importing = true }
            }
            Section {
                Text("GradeSpace 2.0").font(.headline)
                Text("Ваши оценки хранятся на iPhone. Сохраните резервную копию перед удалением или переустановкой приложения.").font(.subheadline).foregroundStyle(.secondary)
                Text("Анимации учитывают настройку iPhone «Уменьшение движения».").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Настройки")
            .sheet(isPresented: $thresholds) { ThresholdEditor() }
            .sheet(isPresented: $sharing) { if let export { ShareSheet(url: export) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 10 * 1024 * 1024 else { throw JournalError.invalid }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10 * 1024 * 1024 else { throw JournalError.invalid }
                    pending = try Journal.decode(data)
                } catch { store.error = "Копия не загружена. " + error.localizedDescription }
            }
            .confirmationDialog("Заменить текущий журнал выбранной копией?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
                Button("Восстановить", role: .destructive) { if let pending { _ = store.commit(pending) }; pending = nil }
            }
    }
}

struct ThresholdEditor: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var three = ""
    @State private var four = ""
    @State private var five = ""
    private var draft: Thresholds? {
        guard let a = Display.parseThreshold(three), let b = Display.parseThreshold(four), let c = Display.parseThreshold(five) else { return nil }
        let t = Thresholds(three: a, four: b, five: c)
        return t.isValid ? t : nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row("Тройка от", text: $three)
                    row("Четвёрка от", text: $four)
                    row("Пятёрка от", text: $five)
                } footer: {
                    Text("Укажите пороги до двух знаков после запятой. Они должны возрастать и быть не больше 5,00. Например: 2,50 → 3,50 → 4,60.")
                }
                if draft == nil { Text("Проверьте значения и порядок порогов.").font(.subheadline).foregroundStyle(.red) }
            }.navigationTitle("Пороги оценок")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { if let draft, store.update({ $0.thresholds = draft }) { dismiss() } }.disabled(draft == nil)
                    }
                }
                .onAppear {
                    three = Display.threshold(store.journal.thresholds.three)
                    four = Display.threshold(store.journal.thresholds.four)
                    five = Display.threshold(store.journal.thresholds.five)
                }
        }.presentationDetents([.medium, .large])
    }
    private func row(_ title: String, text: Binding<String>) -> some View {
        HStack { Text(title); Spacer(); TextField("4,60", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100).accessibilityLabel(title) }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
