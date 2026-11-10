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
        .keyboardDismissal()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}
