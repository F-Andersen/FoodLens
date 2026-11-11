import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiaryStore.self) private var diary
    @AppStorage("backendURL") private var backendURL = ""
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var connection: ConnectionState = .idle

    private enum ConnectionState: Equatable { case idle, checking, ok, failed(String) }

    private var backendURLIsValid: Bool {
        backendURL.trimmingCharacters(in: .whitespaces).isEmpty
            || (try? FoodLensAPI.endpoint(base: backendURL, path: "health")) != nil
    }

    private var activeServer: String? { AppConfig.apiBaseURL(override: backendURL) }

    private func checkConnection() async {
        guard let server = activeServer else { return }
        connection = .checking
        do {
            try await FoodLensAPI.shared.checkHealth(baseURL: server)
            connection = .ok
        } catch {
            connection = .failed(error.localizedDescription)
        }
    }

    var body: some View {
        @Bindable var diary = diary
        Form {
            Section {
                NavigationLink {
                    NutritionPlanView(initialProfile: diary.profileWithLatestWeight)
                } label: {
                    Label("Профіль і норма", systemImage: "person.crop.circle")
                }
                Button {
                    dismiss()
                    onboardingCompleted = false
                } label: {
                    Label("Пройти налаштування знову", systemImage: "arrow.counterclockwise")
                }
            }
            Section {
                LabeledContent("Режим", value: activeServer == nil ? "Аналіз на iPhone" : "AI-сервер")
                TextField(AppConfig.defaultAPIBaseURL.isEmpty ? "https://api.foodlens.example" : AppConfig.defaultAPIBaseURL,
                          text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: backendURL) { _, _ in connection = .idle }
                if !backendURLIsValid {
                    Text("Адреса має починатися з http:// або https://").font(.caption).foregroundStyle(.red)
                }
                if activeServer != nil {
                    Button {
                        Task { await checkConnection() }
                    } label: {
                        HStack {
                            Text("Перевірити з'єднання")
                            Spacer()
                            switch connection {
                            case .idle: EmptyView()
                            case .checking: ProgressView()
                            case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(connection == .checking || !backendURLIsValid)
                    if case .failed(let message) = connection {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
            } header: {
                Text("AI-сервер")
            } footer: {
                Text("API-ключ зберігається на сервері, а не в застосунку. Поле адреси потрібне лише для власного або тестового сервера; без сервера фото аналізується на iPhone.")
            }
            DailyGoalsSection(goals: $diary.goals, profile: diary.profileForEstimates)
            Section("Про застосунок") {
                LabeledContent("Версія", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .navigationTitle("Налаштування")
        .keyboardDismissal()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}

/// Daily goals. In automatic mode the macros follow the calorie goal and the chosen split;
/// in manual mode the grams stay exactly as set and a mismatch is reported, never overwritten.
struct DailyGoalsSection: View {
    @Binding var goals: NutritionGoals
    let profile: NutritionProfile?

    private var calories: Binding<Double> {
        Binding(get: { goals.calories }, set: { goals.setCalories($0) })
    }

    private var automatic: Binding<Bool> {
        Binding(get: { goals.isAutomatic }, set: { isOn in
            goals.setMacroSplit(isOn ? (goals.impliedSplit.flatMap { $0.isValid ? $0 : nil } ?? .balanced) : nil)
        })
    }

    private var split: MacroSplit { goals.macroSplit ?? .balanced }

    private func percentBinding(_ keyPath: WritableKeyPath<MacroSplit, Double>, range: ClosedRange<Double>) -> Binding<Int> {
        Binding(
            get: { Int((split[keyPath: keyPath] * 100).rounded()) },
            set: { newValue in
                var updated = split
                updated[keyPath: keyPath] = min(max(Double(newValue) / 100, range.lowerBound), range.upperBound)
                if updated.isValid { goals.setMacroSplit(updated) }
            }
        )
    }

    var body: some View {
        Section {
            Stepper("Калорії: \(Int(goals.calories.rounded()))", value: calories, in: 1000...5000, step: 50)
            if let profile, let warning = profile.deficitWarning(forCalories: goals.calories) {
                Label(warning, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warning)
            }
            Toggle("БЖВ автоматично від калорій", isOn: automatic)
            if goals.isAutomatic {
                Picker("Пропорції", selection: Binding(
                    get: { split.presetTitle ?? "custom" },
                    set: { title in
                        if let preset = MacroSplit.presets.first(where: { $0.title == title }) { goals.setMacroSplit(preset.split) }
                    }
                )) {
                    ForEach(MacroSplit.presets, id: \.title) { Text($0.title).tag($0.title) }
                    if split.presetTitle == nil { Text("Власні").tag("custom") }
                }
                Stepper("Білки: \(percentBinding(\.protein, range: MacroSplit.proteinRange).wrappedValue) %",
                        value: percentBinding(\.protein, range: MacroSplit.proteinRange), in: 10...40)
                Stepper("Жири: \(percentBinding(\.fat, range: MacroSplit.fatRange).wrappedValue) %",
                        value: percentBinding(\.fat, range: MacroSplit.fatRange), in: 20...45)
                LabeledContent("Вуглеводи", value: "\(Int((split.carbs * 100).rounded())) %")
                LabeledContent("Б / Ж / В", value: "\(Int(goals.protein)) / \(Int(goals.fat)) / \(Int(goals.carbs)) г")
            } else {
                Stepper("Білки: \(Int(goals.protein)) г", value: $goals.protein, in: 20...300, step: 5)
                Stepper("Жири: \(Int(goals.fat)) г", value: $goals.fat, in: 20...250, step: 5)
                Stepper("Вуглеводи: \(Int(goals.carbs)) г", value: $goals.carbs, in: 20...500, step: 5)
                if !goals.macrosMatchCalories {
                    let gap = Int(goals.macroCalorieGap.rounded())
                    Label("БЖВ дають \(Int(goals.macroCalories.rounded())) ккал (\(gap > 0 ? "+" : "")\(gap) від цілі \(Int(goals.calories.rounded())) ккал).",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Theme.warning)
                    Button("Перерахувати БЖВ під \(Int(goals.calories.rounded())) ккал") { goals.alignMacrosToCalories() }
                }
            }
            Stepper("Клітковина: \(Int(goals.fiber)) г", value: $goals.fiber, in: 10...80, step: 1)
            Stepper("Вода: \(Int(goals.waterML)) мл", value: $goals.waterML, in: 500...5000, step: 100)
        } header: {
            Text("Денні цілі")
        } footer: {
            Text(goals.isAutomatic
                 ? "Грами рахуються з калорій: 1 г білків чи вуглеводів — 4 ккал, 1 г жирів — 9 ккал. Пропорції — білки / жири / вуглеводи."
                 : "Ручні цілі не змінюються автоматично. Кнопка перерахунку зберігає ваші пропорції.")
        }
    }
}
