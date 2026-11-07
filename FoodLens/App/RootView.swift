import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case today, scan, progress, assistant, diary

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Сьогодні"
        case .scan: "Сканувати"
        case .progress: "Прогрес"
        case .assistant: "Асистент"
        case .diary: "Щоденник"
        }
    }

    var icon: String {
        switch self {
        case .today: "chart.pie.fill"
        case .scan: "camera.viewfinder"
        case .progress: "chart.xyaxis.line"
        case .assistant: "sparkles"
        case .diary: "book.pages.fill"
        }
    }
}

/// Opens the manual-entry sheet, optionally preset to a meal type.
struct ManualEntryRequest: Identifiable {
    let id = UUID()
    var mealType: MealEntry.MealType
}

struct RootView: View {
    @Environment(DiaryStore.self) private var diary
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var selectedTab = AppTab.today
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { DashboardView(selectedTab: $selectedTab) }
                .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.icon) }
                .tag(AppTab.today)
            NavigationStack { ScanView() }
                .tabItem { Label(AppTab.scan.title, systemImage: AppTab.scan.icon) }
                .tag(AppTab.scan)
            NavigationStack { ProgressScreen() }
                .tabItem { Label(AppTab.progress.title, systemImage: AppTab.progress.icon) }
                .tag(AppTab.progress)
            NavigationStack { FoodAssistantView() }
                .tabItem { Label(AppTab.assistant.title, systemImage: AppTab.assistant.icon) }
                .tag(AppTab.assistant)
            NavigationStack { DiaryView() }
                .tabItem { Label(AppTab.diary.title, systemImage: AppTab.diary.icon) }
                .tag(AppTab.diary)
        }
        .modifier(MinimizingTabBar())
        .safeAreaInset(edge: .top, spacing: 0) {
            if let issue = diary.storageIssue {
                StorageIssueBanner(message: issue) { diary.dismissStorageIssue() }
            }
        }
        .onAppear {
            // Existing users who already set a profile skip onboarding.
            if !onboardingCompleted && diary.profile == nil { showOnboarding = true }
        }
        .onChange(of: onboardingCompleted) { _, completed in
            // "Пройти налаштування знову" in Settings resets the flag.
            // Wait for the Settings sheet to finish dismissing before presenting.
            guard !completed else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView { onboardingCompleted = true; showOnboarding = false }
        }
    }
}

/// On iOS 26+ the Liquid Glass tab bar shrinks while scrolling down.
private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
