import SwiftUI

@main
struct FoodLensApp: App {
    @State private var diary = DiaryStore.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(diary)
                .tint(Theme.accent)
        }
    }
}
