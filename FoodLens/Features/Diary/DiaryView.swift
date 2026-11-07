import SwiftUI

struct DiaryView: View {
    @Environment(DiaryStore.self) private var diary
    @State private var query = ""

    private var filtered: [MealEntry] {
        query.isEmpty ? diary.entries : diary.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let entries = filtered
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Щоденник порожній" : "Нічого не знайдено",
                    systemImage: "fork.knife",
                    description: Text("Додайте страву зі сканера або вручну.")
                )
            } else {
                ForEach(entries) { entry in
                    NavigationLink {
                        EditMealEntryView(entry: entry)
                    } label: {
                        MealRow(entry: entry)
                    }
                    .swipeActions(edge: .leading) {
                        Button { diary.toggleFavorite(id: entry.id) } label: {
                            Label("Обране", systemImage: entry.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.yellow)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { diary.deleteMeal(id: entries[index].id) }
                }
            }
        }
        .searchable(text: $query, prompt: "Пошук у щоденнику")
        .navigationTitle("Щоденник")
    }
}

struct EditMealEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiaryStore.self) private var diary
    let original: MealEntry
    @State private var name: String
    @State private var grams: Double
    @State private var calories: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var fiber: Double
    @State private var mealType: MealEntry.MealType
    @State private var scaleWithWeight = true
    @State private var portion: PortionTracker

    init(entry: MealEntry) {
        original = entry
        _portion = State(initialValue: PortionTracker(grams: entry.grams))
        _name = State(initialValue: entry.name)
        _grams = State(initialValue: entry.grams)
        _calories = State(initialValue: entry.calories.rounded())
        _protein = State(initialValue: entry.protein)
        _carbs = State(initialValue: entry.carbs)
        _fat = State(initialValue: entry.fat)
        _fiber = State(initialValue: entry.fiber)
        _mealType = State(initialValue: entry.mealType)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && grams >= 0 && calories >= 0 && protein >= 0 && carbs >= 0 && fat >= 0 && fiber >= 0
    }

    var body: some View {
        Form {
            Section("Страва") {
                TextField("Назва страви", text: $name, axis: .vertical).lineLimit(1...3)
                Picker("Прийом їжі", selection: $mealType) {
                    ForEach(MealEntry.MealType.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                NumberFieldRow(title: "Вага", value: $grams, unit: "г")
                Toggle("Перераховувати КБЖВ разом із вагою", isOn: $scaleWithWeight)
                NumberFieldRow(title: "Калорії всієї порції", value: $calories, unit: "ккал")
                LabeledContent("На 100 г", value: grams > 0 ? "\(Int((calories / grams * 100).rounded())) ккал" : "—")
            } header: {
                Text("Порція та калорії")
            } footer: {
                Text("Вага 0 означає, що вона невідома.")
            }
            Section("КБЖВ усієї порції") {
                NumberFieldRow(title: "Білки", value: $protein, unit: "г")
                NumberFieldRow(title: "Вуглеводи", value: $carbs, unit: "г")
                NumberFieldRow(title: "Жири", value: $fat, unit: "г")
                NumberFieldRow(title: "Клітковина", value: $fiber, unit: "г")
            }
            Section {
                Button("Зберегти зміни", action: save)
                    .frame(maxWidth: .infinity)
                    .disabled(!isValid)
            } footer: {
                Text("Зміни одразу оновлять денні калорії та показники БЖВ.")
            }
        }
        .navigationTitle("Редагування")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: grams) { _, newValue in
            guard let factor = portion.factor(for: newValue), scaleWithWeight else { return }
            calories *= factor; protein *= factor; carbs *= factor; fat *= factor; fiber *= factor
        }
    }

    private func save() {
        var updated = original
        let factor = Portion.scaleFactor(from: original.grams, to: grams) ?? 1
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.grams = grams
        updated.calories = calories
        updated.protein = protein
        updated.carbs = carbs
        updated.fat = fat
        updated.fiber = fiber
        updated.mealType = mealType
        if scaleWithWeight { updated.ingredients = original.ingredients.map { $0.scaled(by: factor) } }
        diary.update(updated)
        dismiss()
    }
}

struct ManualEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiaryStore.self) private var diary
    @StateObject private var voice = VoiceEntryService()
    @State private var name = ""
    @State private var calories = 300.0
    @State private var grams = 250.0
    @State private var protein = 15.0
    @State private var carbs = 35.0
    @State private var fat = 10.0
    @State private var fiber = 3.0
    @State private var mealType = MealEntry.MealType.suggested(for: .now)

    var body: some View {
        Form {
            Section("Страва") {
                TextField("Наприклад: сирники", text: $name)
                Button {
                    Task { await voice.toggle() }
                } label: {
                    Label(voice.isRecording ? "Зупинити диктування" : "Описати голосом",
                          systemImage: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                if let error = voice.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
                Picker("Прийом їжі", selection: $mealType) { ForEach(MealEntry.MealType.allCases) { Text($0.title).tag($0) } }
                NutritionSlider(title: "Вага", value: $grams, range: 10...1500, unit: "г")
                NutritionSlider(title: "Калорії", value: $calories, range: 0...2000, unit: "ккал")
            }
            Section("Макронутрієнти") {
                NutritionSlider(title: "Білки", value: $protein, range: 0...200, unit: "г")
                NutritionSlider(title: "Вуглеводи", value: $carbs, range: 0...300, unit: "г")
                NutritionSlider(title: "Жири", value: $fat, range: 0...200, unit: "г")
                NutritionSlider(title: "Клітковина", value: $fiber, range: 0...60, unit: "г")
            }
        }
        .navigationTitle("Додати вручну")
        .onChange(of: voice.transcript) { _, value in if !value.isEmpty { name = value } }
        .onDisappear { voice.stop() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Зберегти") {
                    diary.add(MealEntry(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), grams: grams, calories: calories,
                        protein: protein, carbs: carbs, fat: fat, fiber: fiber, mealType: mealType
                    ))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
