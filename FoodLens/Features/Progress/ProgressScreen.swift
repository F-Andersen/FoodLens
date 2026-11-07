import Charts
import SwiftUI

struct ProgressScreen: View {
    @Environment(DiaryStore.self) private var diary
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
                    BarMark(x: .value("День", day, unit: .day), y: .value("Ккал", diary.calories(on: day)))
                        .foregroundStyle(.orange.gradient)
                    RuleMark(y: .value("Ціль", diary.goals.calories))
                        .foregroundStyle(Theme.accent.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 190)
            }
            Section("Вага") {
                if let latest = diary.latestWeight {
                    LabeledContent("Поточна вага", value: "\(latest.kilograms.formatted(.number.precision(.fractionLength(0...1)))) кг")
                } else {
                    Text("Записів ваги ще немає").foregroundStyle(.secondary)
                }
                if diary.weights.count > 1 {
                    Chart(diary.weights.reversed()) { record in
                        LineMark(x: .value("Дата", record.date), y: .value("кг", record.kilograms)).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Дата", record.date), y: .value("кг", record.kilograms))
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
        .sheet(item: $editingWeight) { record in WeightEditView(record: record) }
        .sheet(item: $report) { file in ShareSheet(url: file.url).presentationDetents([.medium, .large]) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: makeReport) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Поділитися PDF-звітом")
            }
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
