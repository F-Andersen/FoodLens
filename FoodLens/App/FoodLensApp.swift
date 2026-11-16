import SwiftUI

@main
struct FoodLensApp: App {
    @State private var diary = DiaryStore.makeDefault()
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
