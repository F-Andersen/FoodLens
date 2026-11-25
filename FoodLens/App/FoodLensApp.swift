import SwiftUI

@main
struct FoodLensApp: App {
    #if DEBUG
    @State private var diary = DiaryStore.launchStore
    #else
    @State private var diary = DiaryStore.makeDefault()
    #endif
    @State private var health = HealthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(diary)
                .environment(health)
                .tint(Theme.accent)
        }
    }
}
