import SwiftUI

/// First-launch flow: welcome → body data → calculated goals.
struct OnboardingView: View {
    @Environment(DiaryStore.self) private var diary
    let finish: () -> Void

    private enum Step: Int { case welcome, profile, result }

    @State private var step = Step.welcome
    @State private var profile = NutritionProfile()

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .profile: profileForm
                case .result: result
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .toolbar {
                if step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Назад") { go(to: Step(rawValue: step.rawValue - 1) ?? .welcome) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Пропустити", action: finish)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear { profile = diary.profileWithLatestWeight }
    }

    private func go(to newStep: Step) {
        withAnimation(.smooth) { step = newStep }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 112, height: 112)
                .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.3), radius: 20, y: 10)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.s) {
                Text("Вітаємо у FoodLens").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("Харчування під контролем без зайвих зусиль").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: Spacing.l) {
                Feature(icon: "camera.fill", tint: Theme.accent, title: "Фото замість підрахунків", text: "Сфотографуйте тарілку — калорії та БЖВ оцінимо автоматично.")
                Feature(icon: "chart.pie.fill", tint: Macro.protein.color, title: "Норма саме для вас", text: "Розрахуємо калорії, білки, жири, вуглеводи та воду.")
                Feature(icon: "chart.xyaxis.line", tint: .orange, title: "Прогрес і звіти", text: "Вага, калорії за тиждень і PDF-звіт для лікаря.")
            }
            .padding(.horizontal)
            Spacer()
            Button { go(to: .profile) } label: {
                Text("Налаштувати норму").font(.headline).frame(maxWidth: .infinity).padding(.vertical, Spacing.s)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding()
    }

    private var profileForm: some View {
        Form {
            Section {
                Text("Ці дані потрібні, щоб розрахувати вашу денну норму. Вони зберігаються лише на цьому iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ProfileFormSection(profile: $profile)
        }
        .navigationTitle("Про вас")
        .safeAreaInset(edge: .bottom) {
            Button { go(to: .result) } label: {
                Text("Розрахувати").font(.headline).frame(maxWidth: .infinity).padding(.vertical, Spacing.s)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!profile.isValid)
            .padding()
        }
    }

    private var result: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Ваша денна норма").font(.largeTitle.bold())
                    Text("Мета: \(profile.goal.title.lowercased()) · \(profile.activity.title.lowercased())")
                        .foregroundStyle(.secondary)
                }
                GoalsSummaryCard(goals: profile.calculatedGoals).cardStyle()
                Text("Розрахунок орієнтовний (формула Міффліна — Сан Жеора). Цілі можна змінити будь-коли в налаштуваннях. За наявності захворювань узгодьте раціон із лікарем.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            Button {
                diary.profile = profile
                diary.goals = profile.calculatedGoals
                finish()
            } label: {
                Text("Почати").font(.headline).frame(maxWidth: .infinity).padding(.vertical, Spacing.s)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding()
        }
    }
}

private struct Feature: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
