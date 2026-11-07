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
        case .scan: "camera.fill"
        case .progress: "chart.xyaxis.line"
        case .assistant: "sparkles"
        case .diary: "list.bullet"
        }
    }
}

struct RootView: View {
    @Environment(DiaryStore.self) private var diary
    @State private var showManualEntry = false
    @State private var showSettings = false
    @State private var selectedTab = AppTab.today

    var body: some View {
        VStack(spacing: 0) {
            if let issue = diary.storageIssue {
                StorageIssueBanner(message: issue) { diary.dismissStorageIssue() }
            }
            Group {
                switch selectedTab {
                case .today:
                    NavigationStack { DashboardView(showManualEntry: $showManualEntry, showSettings: $showSettings) }
                case .scan:
                    NavigationStack { ScanView() }
                case .progress:
                    NavigationStack { ProgressScreen() }
                case .assistant:
                    NavigationStack { FoodAssistantView() }
                case .diary:
                    NavigationStack { DiaryView() }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in BottomTab(tab: tab, selected: $selectedTab) }
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider().opacity(0.45) }
        }
        .sheet(isPresented: $showManualEntry) { NavigationStack { ManualEntryView() } }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
    }
}

private struct BottomTab: View {
    let tab: AppTab
    @Binding var selected: AppTab

    var body: some View {
        Button { selected = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon).font(.title3)
                Text(tab.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected == tab ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == tab ? .isSelected : [])
    }
}
