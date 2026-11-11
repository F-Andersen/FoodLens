import Charts
import SwiftUI

struct ProgressScreen: View {
    @Environment(DiaryStore.self) private var diary
    @Environment(HealthService.self) private var health
    @State private var activityMetric = ActivityMetric.steps
    @State private var weightText = ""
    @State private var editingWeight: WeightRecord?
    @State private var report: ReportFile?
    @State private var reportError: String?

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.reversed()
    }

    var body: some View {
        List {
            Section("Калорії за 7 днів") {
                Chart(days, id: \.self) { day in
                    BarMark(x: .value("День", day, unit: .day), y: .value("Ккал", diary.totals(on: day).calories))
                        .foregroundStyle(.orange.gradient)
                    RuleMark(y: .value("Ціль", diary.goals.calories))
                        .foregroundStyle(Theme.accent.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 190)
            }
            activitySection
            balanceSection
            macroSection
            Section("Вага") {
                if let latest = diary.latestWeight {
                    LabeledContent("Поточна вага", value: "\(latest.kilograms.formatted(.number.precision(.fractionLength(0...1)))) кг")
                } else {
                    Text("Записів ваги ще немає").foregroundStyle(.secondary)
                }
                if diary.weights.count > 1 {
                    Chart {
                        ForEach(diary.weights.reversed()) { record in
                            LineMark(x: .value("Дата", record.date), y: .value("кг", record.kilograms)).interpolationMethod(.catmullRom)
                            PointMark(x: .value("Дата", record.date), y: .value("кг", record.kilograms))
                        }
                        if let target = diary.profile?.targetWeightKG {
                            RuleMark(y: .value("Ціль", target))
                                .foregroundStyle(Theme.accent.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("ціль \(target.formatted(.number.precision(.fractionLength(0...1)))) кг")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 190)
                }
                HStack {
                    TextField("Введіть вагу", text: $weightText).keyboardType(.decimalPad)
                    Text("кг").foregroundStyle(.secondary)
                    Button("Записати", action: addWeight).disabled(WeightRecord.parse(weightText) == nil)
                }
                if !weightText.isEmpty, WeightRecord.parse(weightText) == nil {
                    Text("Введіть вагу від 30 до 350 кг").font(.caption).foregroundStyle(.red)
                }
                ForEach(diary.weights.prefix(10)) { record in
                    Button { editingWeight = record } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                Text("\(record.kilograms.formatted(.number.precision(.fractionLength(0...1)))) кг").foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(Theme.accent)
                        }
                    }
                    .swipeActions {
                        Button("Видалити", role: .destructive) { diary.deleteWeight(id: record.id) }
                    }
                }
            }
            Section("Звички сьогодні") {
                LabeledContent("Вода", value: "\(Int(diary.waterToday)) мл")
                LabeledContent("Записано страв", value: "\(diary.todayEntries.count)")
                LabeledContent("Клітковина", value: "\(Int(diary.todayTotals.fiber)) г")
            }
            if let reportError {
                Section { Text(reportError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Мій прогрес")
        .keyboardDismissal()
        .task { if health.lastUpdated == nil { await health.refresh() } }
        .refreshable { await health.refresh() }
        .sheet(item: $editingWeight) { record in WeightEditView(record: record) }
        .sheet(item: $report) { file in ShareSheet(url: file.url).presentationDetents([.medium, .large]) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: makeReport) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Поділитися PDF-звітом")
            }
        }
    }

    enum ActivityMetric: String, CaseIterable, Identifiable {
        case steps = "Кроки"
        case calories = "Активні ккал"
        var id: Self { self }
    }

    @ViewBuilder
    private var balanceSection: some View {
        let profile = diary.profileForEstimates
        let days = DayBalance.week(snapshot: health.snapshot, profile: profile,
                                   eaten: { diary.totals(on: $0).calories })
        Section {
            if days.isEmpty {
                Text(profile == nil && health.snapshot.restingCalories == 0
                     ? "Вкажіть профіль у «Норма та меню» або дозвольте читати енергію спокою з Apple Health."
                     : "Ще немає днів із записаною їжею.")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(days) { day in
                        BarMark(x: .value("День", day.day, unit: .day), y: .value("Дефіцит", day.deficit))
                            .foregroundStyle(day.deficit >= 0 ? Theme.accent : Theme.warning)
                            .opacity(day.isToday ? 0.55 : 1)
                    }
                    RuleMark(y: .value("Нуль", 0)).foregroundStyle(.secondary)
                }
                .frame(height: 170)
                if let week = WeekEnergySummary(days) {
                    LabeledContent("Спожито в середньому", value: "\(Int(week.averageEaten.rounded()).formatted()) ккал")
                    LabeledContent("Витрати в середньому", value: "\(Int(week.averageBurned.rounded()).formatted()) ккал")
                    let average = Int(week.averageDeficit.rounded())
                    LabeledContent(average >= 0 ? "Орієнтовний дефіцит" : "Орієнтовний профіцит",
                                   value: "\(abs(average).formatted()) ккал/день")
                    LabeledContent("Орієнтовна зміна ваги",
                                   value: "\(week.estimatedWeightChangeKG.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))) кг")
                } else {
                    Text("Середні значення з'являться після першого завершеного дня із записами.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Енергобаланс за 7 днів")
        } footer: {
            Text("Витрачено (енергія спокою + активність) мінус спожите. Вище нуля — дефіцит, нижче — профіцит. Сьогоднішній стовпчик блідіший і не входить у середні: день ще триває. Дні без записів їжі пропущено. Зміна ваги — грубий орієнтир (7 700 ккал ≈ 1 кг), а не прогноз: вода та похибка оцінок сильно впливають на результат.")
        }
    }

    private struct MacroDay: Identifiable {
        let day: Date
        let macro: Macro
        let kcal: Double
        var id: String { "\(day.timeIntervalSince1970)-\(macro.title)" }
    }

    @ViewBuilder
    private var macroSection: some View {
        let logged = days.filter { !diary.entries(on: $0).isEmpty }
        Section {
            if logged.isEmpty {
                Text("Ще немає записів їжі за тиждень.").foregroundStyle(.secondary)
            } else {
                let points = logged.flatMap { day in
                    let totals = diary.totals(on: day)
                    return [MacroDay(day: day, macro: .protein, kcal: totals.protein * MacroEnergy.protein),
                            MacroDay(day: day, macro: .fat, kcal: totals.fat * MacroEnergy.fat),
                            MacroDay(day: day, macro: .carbs, kcal: totals.carbs * MacroEnergy.carbs)]
                }
                Chart(points) { point in
                    BarMark(x: .value("День", point.day, unit: .day), y: .value("ккал", point.kcal))
                        .foregroundStyle(by: .value("Макро", point.macro.title))
                }
                .chartForegroundStyleScale(domain: [Macro.protein.title, Macro.fat.title, Macro.carbs.title],
                                           range: [Macro.protein.color, Macro.fat.color, Macro.carbs.color])
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 170)
                let average = NutritionTotals.average(of: logged.map { diary.totals(on: $0) })
                ForEach([Macro.protein, .fat, .carbs, .fiber]) { macro in
                    LabeledContent(macro.title,
                                   value: "\(Int(macro.value(in: average).rounded())) / \(Int(macro.goal(in: diary.goals).rounded())) г")
                }
            }
        } header: {
            Text("БЖВ за 7 днів")
        } footer: {
            Text("Стовпчики — енергія з білків, жирів і вуглеводів за день. Нижче — середнє за дні із записами проти денної цілі.")
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        let week = health.snapshot.week
        Section {
            if week.contains(where: { $0.steps > 0 || $0.activeCalories > 0 }) {
                Picker("Показник", selection: $activityMetric) {
                    ForEach(ActivityMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Chart(week) { day in
                    BarMark(
                        x: .value("День", day.day, unit: .day),
                        y: .value(activityMetric.rawValue, activityMetric == .steps ? day.steps : day.activeCalories)
                    )
                    .foregroundStyle(activityMetric == .steps ? Ring.stand.color.gradient : Ring.move.color.gradient)
                }
                .frame(height: 170)
                LabeledContent("Середнє за день",
                               value: activityMetric == .steps
                                   ? "\(health.snapshot.weekAverageSteps.formatted()) кроків"
                                   : "\(health.snapshot.weekAverageActiveCalories.formatted()) ккал")
            } else {
                Text(health.isLoading ? "Завантажуємо дані з Apple Health…" : "Даних з Apple Health за тиждень ще немає.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Активність за 7 днів")
        } footer: {
            Text("Кроки та активні калорії з Apple Health. Потягніть вниз, щоб оновити.")
        }
    }

    private func addWeight() {
        guard let value = WeightRecord.parse(weightText) else { return }
        diary.addWeight(value)
        weightText = ""
    }

    /// Builds a fresh report on every tap, so it always reflects the current diary.
    private func makeReport() {
        do {
            let url = try FoodReport.make(entries: diary.entries, weights: diary.weights, goals: diary.goals)
            reportError = nil
            report = ReportFile(url: url)
        } catch {
            reportError = "Не вдалося створити звіт."
        }
    }
}

struct ReportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct WeightEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiaryStore.self) private var diary
    let record: WeightRecord
    @State private var weightText: String

    init(record: WeightRecord) {
        self.record = record
        _weightText = State(initialValue: record.kilograms.formatted(.number.precision(.fractionLength(0...1))))
    }

    var body: some View {
        NavigationStack {
            Form {
            Section("Вага") {
                    HStack {
                        TextField("Вага", text: $weightText).keyboardType(.decimalPad)
                        Text("кг").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Змінити запис")
            .keyboardDismissal()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        guard let value = WeightRecord.parse(weightText) else { return }
                        diary.updateWeight(id: record.id, kilograms: value)
                        dismiss()
                    }
                    .disabled(WeightRecord.parse(weightText) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
