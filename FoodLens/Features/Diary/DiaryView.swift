import SwiftUI

struct DiaryView: View {
    @Environment(DiaryStore.self) private var diary
    @State private var query = ""
    @State private var manualEntry: ManualEntryRequest?

    private var days: [DiaryDay] {
        let entries = query.isEmpty ? diary.entries : diary.entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return DiaryDay.group(entries)
    }

    var body: some View {
        let days = days
        List {
            if days.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "Щоденник порожній" : "Нічого не знайдено",
                    systemImage: query.isEmpty ? "book.pages" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Сфотографуйте страву або додайте її вручну." : "Спробуйте інший запит.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(days) { day in
                Section {
                    ForEach(day.entries) { entry in
                        NavigationLink {
                            EditMealEntryView(entry: entry)
                        } label: {
                            MealRow(entry: entry)
                        }
                        .swipeActions(edge: .leading) {
                            Button { diary.toggleFavorite(id: entry.id) } label: {
                                Label(entry.isFavorite ? "Прибрати з обраного" : "В обране", systemImage: entry.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { diary.deleteMeal(id: entry.id) } label: {
                                Label("Видалити", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(day.title())
                        Spacer()
                        Text("\(day.totals.kcal) ккал").monospacedDigit()
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Пошук у щоденнику")
        .navigationTitle("Щоденник")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { manualEntry = ManualEntryRequest(mealType: .suggested(for: .now)) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Додати страву")
            }
        }
        .sheet(item: $manualEntry) { request in
            NavigationStack { ManualEntryView(mealType: request.mealType) }
        }
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
        _calories = State(initialValue: entry.calories)
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
        .keyboardDismissal()
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
    @State private var calories = 0.0
    @State private var grams = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var fiber = 0.0
    @State private var mealType: MealEntry.MealType
    @State private var savedTick = 0

    init(mealType: MealEntry.MealType = .suggested(for: .now)) {
        _mealType = State(initialValue: mealType)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && calories >= 0 && grams >= 0
    }

    var body: some View {
        Form {
            let favorites = diary.entries.uniqueFavorites
            if !favorites.isEmpty {
                Section("Обране") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.s) {
                            ForEach(favorites.prefix(12)) { favorite in
                                Button { fill(from: favorite) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(favorite.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                        Text("\(favorite.kcal) ккал").font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                                    .frame(maxWidth: 180, alignment: .leading)
                                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: Spacing.s, leading: Spacing.l, bottom: Spacing.s, trailing: Spacing.l))
                }
            }
            Section("Страва") {
                HStack {
                    TextField("Наприклад: сирники зі сметаною", text: $name, axis: .vertical)
                    Button {
                        Task { await voice.toggle() }
                    } label: {
                        Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.title3)
                            .foregroundStyle(voice.isRecording ? .red : Theme.accent)
                            .symbolEffect(.pulse, isActive: voice.isRecording)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(voice.isRecording ? "Зупинити диктування" : "Описати голосом")
                }
                if let error = voice.errorMessage { Text(error).font(.caption).foregroundStyle(Theme.warning) }
                Picker("Прийом їжі", selection: $mealType) {
                    ForEach(MealEntry.MealType.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
            }
            Section {
                NumberFieldRow(title: "Калорії", value: $calories, unit: "ккал")
                NumberFieldRow(title: "Вага порції", value: $grams, unit: "г")
            } header: {
                Text("Порція")
            } footer: {
                Text("Якщо вага невідома, залиште 0.")
            }
            Section("БЖВ") {
                NumberFieldRow(title: Macro.protein.title, value: $protein, unit: "г")
                NumberFieldRow(title: Macro.fat.title, value: $fat, unit: "г")
                NumberFieldRow(title: Macro.carbs.title, value: $carbs, unit: "г")
                NumberFieldRow(title: Macro.fiber.title, value: $fiber, unit: "г")
            }
        }
        .navigationTitle("Додати страву")
        .keyboardDismissal()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: voice.transcript) { _, value in if !value.isEmpty { name = value } }
        .onDisappear { voice.stop() }
        .sensoryFeedback(.success, trigger: savedTick)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Зберегти", action: save).disabled(!canSave)
            }
        }
    }

    private func fill(from entry: MealEntry) {
        name = entry.name; calories = entry.calories.rounded(); grams = entry.grams
        protein = entry.protein; carbs = entry.carbs; fat = entry.fat; fiber = entry.fiber
    }

    private func save() {
        diary.add(MealEntry(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines), grams: grams, calories: calories,
            protein: protein, carbs: carbs, fat: fat, fiber: fiber, mealType: mealType
        ))
        savedTick += 1
        dismiss()
    }
}
