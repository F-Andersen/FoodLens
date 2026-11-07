import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DiaryStore.self) private var diary
    @AppStorage("backendURL") private var backendURL = ""

    private var backendURLIsValid: Bool {
        backendURL.trimmingCharacters(in: .whitespaces).isEmpty || (try? FoodAIService.endpoint(from: backendURL)) != nil
    }

    var body: some View {
        @Bindable var diary = diary
        Form {
            Section {
                TextField("https://foodlens.example.com", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if !backendURLIsValid {
                    Text("Адреса має починатися з http:// або https://").font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("AI-сервер")
            } footer: {
                Text("API-ключ зберігається на сервері, а не в застосунку. Без адреси фото аналізується на iPhone.")
            }
            Section("Денні цілі") {
                Stepper("Калорії: \(Int(diary.goals.calories))", value: $diary.goals.calories, in: 1000...5000, step: 50)
                Stepper("Білки: \(Int(diary.goals.protein)) г", value: $diary.goals.protein, in: 20...300, step: 5)
                Stepper("Вуглеводи: \(Int(diary.goals.carbs)) г", value: $diary.goals.carbs, in: 20...500, step: 5)
                Stepper("Жири: \(Int(diary.goals.fat)) г", value: $diary.goals.fat, in: 20...250, step: 5)
                Stepper("Клітковина: \(Int(diary.goals.fiber)) г", value: $diary.goals.fiber, in: 10...80, step: 1)
                Stepper("Вода: \(Int(diary.goals.waterML)) мл", value: $diary.goals.waterML, in: 500...5000, step: 100)
            }
            Section("Про застосунок") {
                LabeledContent("Версія", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .navigationTitle("Налаштування")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}
