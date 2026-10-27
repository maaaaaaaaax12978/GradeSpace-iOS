import SwiftUI
import UniformTypeIdentifiers

@main
struct GradeSpaceApp: App {
    @StateObject private var store: JournalStore
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Ball-UI-tests/journal.json")
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            let testStore = JournalStore(url: url)
            testStore.update {
                $0.subjects = [
                    Subject(id: "math", name: "Математика", marks: [Mark(value: 4), Mark(value: 5)]),
                    Subject(id: "physics", name: "Физика", color: 1, marks: [Mark(value: 3), Mark(value: 4)])
                ]
            }
            _store = StateObject(wrappedValue: testStore)
            return
        }
        #endif
        _store = StateObject(wrappedValue: JournalStore())
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(store.journal.theme == "dark" ? .dark : store.journal.theme == "light" ? .light : nil)
                .tint(.teal)
        }
    }
}

private let subjectColors: [Color] = [.indigo, .teal, .orange, .pink, .blue, .purple]

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
        .alert("Балл", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @ScaledMetric(relativeTo: .headline) private var rowHeight: CGFloat = 56
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...4, id: \.self) { quarter in
                let active = store.journal.lastQuarter == quarter
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.8)) {
                        _ = store.update { $0.lastQuarter = quarter }
                    }
                } label: {
                    Text(active ? "\(quarterRoman[quarter - 1]) четверть" : quarterRoman[quarter - 1])
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: rowHeight)
                        .contentShape(Capsule())
                        .background {
                            if active {
                                Capsule().fill(Color.teal.opacity(0.2))
                                    .matchedGeometryEffect(id: "quarter", in: selection)
                            }
                        }
                }.buttonStyle(PressStyle())
                    .accessibilityLabel("\(quarterRoman[quarter - 1]) четверть")
                    .accessibilityIdentifier("quarter.\(quarter)")
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
        }.padding(4).background(.ultraThinMaterial, in: Capsule())
    }
}

private let quarterRoman = ["I", "II", "III", "IV"]

struct SubjectsView: View {
    @EnvironmentObject private var store: JournalStore
    @State private var adding = false
    @State private var editing: Subject?
    @State private var deleting: Subject?
    @State private var closingAll = false
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                QuarterPicker()
                if !store.journal.subjects.isEmpty {
                    QuarterCompletionCard { closingAll = true }
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Каждая оценка\nменяет картину.").font(.title2.bold())
                        Text("Посмотрите, что будет дальше.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 42)).foregroundStyle(.teal.gradient)
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
        .sheet(isPresented: $closingAll) { QuarterCompletionSheet(quarter: store.journal.lastQuarter) }
        .confirmationDialog("Удалить предмет и все его оценки?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                if let s = deleting { store.update { $0.subjects.removeAll { $0.id == s.id } } }
                deleting = nil
            }
        }
    }
}

struct QuarterCompletionCard: View {
    @EnvironmentObject private var store: JournalStore
    let open: () -> Void
    var body: some View {
        let quarter = store.journal.lastQuarter
        let total = store.journal.subjects.count
        let closed = store.journal.subjects.filter { $0.closedQuarters.contains(quarter) }.count
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(closed == total ? "Четверть завершена" : "Итоги \(quarterRoman[quarter - 1]) четверти", systemImage: closed == total ? "checkmark.seal.fill" : "flag.checkered")
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text("Завершено предметов: \(closed) из \(total)").font(.subheadline).foregroundStyle(.secondary)
            Button(action: open) {
                Text(closed == total ? "Посмотреть итоги" : "Завершить всю четверть")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("quarter.review.all")
        }.modifier(Surface())
    }
}

struct QuarterCompletionSheet: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    let quarter: Int
    @State private var finals: [String: Int] = [:]
    @State private var loaded = false
    private var openSubjects: [Subject] { store.journal.subjects.filter { !$0.closedQuarters.contains(quarter) } }
    private var canFinish: Bool {
        !openSubjects.isEmpty && openSubjects.allSatisfy { (1...5).contains(finals[$0.id] ?? 0) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Проверьте итоги всех предметов. Расчёт учитывает настоящие оценки, их веса и общий порог школы.")
                        .font(.subheadline)
                } footer: { Text("Призрачные оценки не входят в итог. Зафиксированные ранее итоги сохранятся.") }
                Section("Предметы") {
                    ForEach(store.journal.subjects) { subject in
                        resultRow(subject)
                    }
                }
                if !openSubjects.isEmpty {
                    Section {
                        Button {
                            let results = Dictionary(uniqueKeysWithValues: openSubjects.compactMap { s in
                                finals[s.id].map { (s.id, $0) }
                            })
                            if store.finishQuarter(quarter, finals: results) { dismiss() }
                        } label: {
                            Text("Завершить всю четверть").bold().frame(maxWidth: .infinity, minHeight: 44)
                        }.disabled(!canFinish).accessibilityIdentifier("quarter.finish.all")
                    } footer: {
                        Text(canFinish ? "Все итоги будут сохранены одним действием. Оценки завершённой четверти будут защищены от изменений." : "Для предметов без настоящих оценок выберите итог учителя вручную. После этого можно завершить четверть целиком.")
                    }
                }
            }.navigationTitle("\(quarterRoman[quarter - 1]) четверть")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
                .onAppear {
                    guard !loaded else { return }
                    finals = store.journal.suggestedFinals(for: quarter)
                    loaded = true
                }
        }.presentationDetents([.large])
    }
    @ViewBuilder
    private func resultRow(_ subject: Subject) -> some View {
        if subject.closedQuarters.contains(quarter) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(subject.name).font(.headline)
                    Label("Уже завершён", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(subject.quarterFinals[String(quarter)] ?? 0)).font(.title2.bold())
            }.padding(.vertical, 5)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text(subject.name).font(.headline)
                let marks = subject.marks(in: quarter)
                Text(marks.isEmpty ? "Нет настоящих оценок — укажите итог вручную" : "Средний \(Display.average(marks)) · оценок: \(marks.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Итог", selection: Binding(get: { finals[subject.id] ?? 0 }, set: { finals[subject.id] = $0 })) {
                    Text("Указать оценку").tag(0)
                    ForEach(1...5, id: \.self) { Text(String($0)).tag($0) }
                }.accessibilityIdentifier("quarter.final.\(subject.id)")
            }.padding(.vertical, 5)
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
                    if subject.closedQuarters.contains(store.journal.lastQuarter) {
                        Text("Завершён · итог \(subject.quarterFinals[String(store.journal.lastQuarter)] ?? 0)")
                    } else {
                        Text("Оценок: \(marks.count)")
                        if forecast.count > marks.count { Text("· прогноз \(Display.average(forecast))").foregroundStyle(.teal) }
                    }
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
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(Display.average(forecast)).font(.title2.bold().monospacedDigit()).contentTransition(.numericText())
                        if let grade = GradeMath.grade(forecast, thresholds: store.journal.thresholds) {
                            Text("Итог \(grade)").font(.caption.bold())
                        }
                    }
                }.foregroundStyle(.white)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Примерьте будущие оценки ниже").font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.0, green: 0.65, blue: 0.51), Color(red: 0.0, green: 0.34, blue: 0.33)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 32))
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
            HStack { Label("Учебный год", systemImage: "calendar").font(.headline); Spacer(); Text(GradeMath.annual(s, thresholds: store.journal.thresholds).map(String.init) ?? "—").font(.title2.bold()) }
            HStack {
                ForEach(1...4, id: \.self) { q in
                    VStack(spacing: 7) {
                        Text(["I", "II", "III", "IV"][q - 1]).font(.caption).foregroundStyle(.secondary)
                        Text(s.closedQuarters.contains(q) ? String(s.quarterFinals[String(q)] ?? 0) : "—").font(.headline)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("Годовая — среднее итогов четырёх завершённых четвертей с общим порогом школы.").font(.caption).foregroundStyle(.secondary)
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
    var showQuickAdd = true
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
                                    .foregroundStyle(ghost ? Color.teal : .primary)
                                    .background((ghost ? Color.teal : Color.primary).opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(ghost ? Color.teal.opacity(0.45) : .clear, style: StrokeStyle(lineWidth: 1, dash: ghost ? [4, 3] : [])))
                            }.buttonStyle(PressStyle())
                                .accessibilityLabel("\(ghost ? "Призрачная оценка" : "Оценка") \(mark.value), вес \(mark.weight). \(mark.note). Изменить")
                                .transition(.scale(scale: 0.65).combined(with: .opacity))
                        }
                    }
                }
                if showQuickAdd { HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            perform {
                                if store.editSubject(subjectID, { $0.marks.append(Mark(value: value, ghost: ghost, quarter: q)) }) { feedback += 1 }
                            }
                        } label: {
                            Text(String(value)).font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 48)
                                .background(ghost ? Color.teal.opacity(0.12) : Color.teal, in: RoundedRectangle(cornerRadius: 15))
                                .foregroundStyle(ghost ? Color.teal : .white)
                        }.buttonStyle(PressStyle()).accessibilityLabel("Добавить \(ghost ? "призрачную " : "")оценку \(value)")
                    }
                }.disabled(s.marks.count >= 20_000) }
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
                    ForecastSubjectContent(subjectID: id, quarter: store.journal.lastQuarter)
                        .id("\(id):\(store.journal.lastQuarter)")
                }
            }.padding(20).padding(.bottom, 30)
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Что, если…")
    }
}

struct ForecastSubjectContent: View {
    @EnvironmentObject private var store: JournalStore
    let subjectID: String
    let quarter: Int
    @State private var trial = TrialGrades()
    var body: some View {
        if let subject = store.subject(subjectID) {
            let saved = subject.marks(in: quarter, forecast: true)
            let preview = saved + trial.previewMarks(in: quarter)
            AverageHero(actual: subject.marks(in: quarter), forecast: preview)
            if subject.closedQuarters.contains(quarter) {
                ContentUnavailableView("Четверть завершена", systemImage: "lock.fill", description: Text("Выберите другую четверть или откройте эту снова в предмете."))
            } else {
                TrialPanel(subjectID: subjectID, quarter: quarter, trial: $trial, preview: preview)
                MarkSection(subjectID: subjectID, ghost: true, showQuickAdd: false)
            }
            Text("Примерка сбрасывается при смене предмета или четверти. Настоящие оценки от неё не меняются.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TrialPanel: View {
    @EnvironmentObject private var store: JournalStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let subjectID: String
    let quarter: Int
    @Binding var trial: TrialGrades
    let preview: [Mark]
    @State private var savedFeedback = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Быстрая примерка", systemImage: "wand.and.stars").font(.headline)
            Text("Выберите, сколько разных оценок хотите примерить. Средний наверху изменится сразу — сохранять оценки для расчёта не нужно.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(Array((1...5).reversed()), id: \.self) { grade in
                Stepper(value: Binding(get: { trial.quantity(for: grade) }, set: { count in
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                        trial.setQuantity(count, for: grade)
                    }
                }), in: 0...100) {
                    HStack(spacing: 12) {
                        Text(String(grade)).font(.title3.bold()).frame(width: 42, height: 44)
                            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        Text("× \(trial.quantity(for: grade))").font(.headline.monospacedDigit()).contentTransition(.numericText())
                    }
                }.accessibilityLabel("Количество оценок \(grade)")
                    .accessibilityValue(String(trial.quantity(for: grade)))
                    .accessibilityIdentifier("trial.grade.\(grade)")
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Средний с примеркой").font(.caption).foregroundStyle(.secondary)
                    Text(Display.average(preview)).font(.largeTitle.bold().monospacedDigit())
                        .contentTransition(.numericText()).accessibilityIdentifier("trial.average")
                }
                Spacer(minLength: 10)
                if let grade = GradeMath.grade(preview, thresholds: store.journal.thresholds) {
                    Text("Итог \(grade)").font(.headline).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.teal.opacity(0.12), in: Capsule())
                }
            }.padding(.vertical, 8)
            let needed = GradeMath.fivesNeeded(preview, threshold: store.journal.thresholds.five)
            Label(needed.map { $0 == 0 ? "Пятёрка уже в прогнозе" : "До пятёрки: ещё \($0) оценок «5» с весом 1" } ?? "При пороге 5,00 достичь пятёрки новыми оценками нельзя", systemImage: "scope")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                if store.saveTrial(trial, subjectID: subjectID, quarter: quarter) {
                    trial = TrialGrades()
                    savedFeedback += 1
                }
            } label: {
                Text("Добавить в сценарий (\(trial.count))").frame(maxWidth: .infinity, minHeight: 30)
            }.buttonStyle(.borderedProminent).controlSize(.large).disabled(trial.count == 0)
                .accessibilityIdentifier("trial.save")
            Button("Сбросить примерку", role: .destructive) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { trial = TrialGrades() }
            }.frame(maxWidth: .infinity, minHeight: 44).disabled(trial.count == 0)
                .accessibilityIdentifier("trial.reset")
            Text("Оценки сохранятся только по кнопке «Добавить в сценарий». Вес каждой — 1.")
                .font(.caption).foregroundStyle(.secondary)
        }.modifier(Surface())
            .sensoryFeedback(.selection, trigger: trial) { _, _ in store.journal.haptics }
            .sensoryFeedback(.success, trigger: savedFeedback) { _, _ in store.journal.haptics }
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
                ForEach([5, 4, 3, 2], id: \.self) { grade in
                    HStack { Text("Оценка \(grade)"); Spacer(); Text("от \(Display.threshold(store.journal.thresholds.value(for: grade)))").foregroundStyle(.secondary).monospacedDigit() }
                }
                Button("Изменить общий порог") { thresholds = true }
            } header: { Text("Правила школы") } footer: {
                Text("Один порог действует для всех оценок: 4,60 → 5, 3,60 → 4, 2,60 → 3. Граница включается. Все оценки имеют вес 1, если вы не указали другой. Завершённые четверти сохраняют зафиксированный итог.")
            }.disabled(store.loadFailed)
            Section("Резервная копия") {
                Button("Сохранить в Файлы", systemImage: "square.and.arrow.up") {
                    do { export = try store.exportURL(); sharing = true }
                    catch { store.error = error.localizedDescription }
                }.disabled(store.loadFailed)
                Button("Восстановить JSON-копию", systemImage: "square.and.arrow.down") { importing = true }
            }
            Section {
                Text("Балл 2.1").font(.headline)
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
    @State private var five = ""
    private var draft: Thresholds? {
        guard let value = Display.parseThreshold(five), (400...500).contains(value) else { return nil }
        return Thresholds(five: value)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Пятёрка начинается с")
                        Spacer()
                        TextField("4,60", text: $five).keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing).frame(width: 82)
                            .accessibilityLabel("Общий порог: пятёрка от")
                            .accessibilityIdentifier("threshold.common")
                        if !five.isEmpty {
                            Button { five = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Очистить порог")
                                .accessibilityIdentifier("threshold.clear")
                        }
                    }
                } header: { Text("Один порог для всех оценок") } footer: {
                    Text("Например, 4,60 для пятёрки автоматически означает 3,60 для четвёрки, 2,60 для тройки и 1,60 для двойки. Правило применяется также к расчётной годовой.")
                }
                if let draft {
                    Section("Получится автоматически") {
                        ForEach([5, 4, 3, 2], id: \.self) { grade in
                            HStack {
                                Text("Оценка \(grade)")
                                Spacer()
                                Text("от \(Display.threshold(draft.value(for: grade)))").monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Укажите значение от 4,00 до 5,00, не больше двух знаков после запятой.")
                        .font(.subheadline).foregroundStyle(.red)
                }
            }.navigationTitle("Общий порог")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { if let draft, store.update({ $0.thresholds = draft }) { dismiss() } }.disabled(draft == nil)
                    }
                }
                .onAppear { five = Display.threshold(store.journal.thresholds.five) }
        }.presentationDetents([.large])
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

