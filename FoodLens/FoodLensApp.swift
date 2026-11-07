import SwiftUI

@main
struct FoodLensApp: App {
    @StateObject private var diary = DiaryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(diary)
                .tint(Theme.accent)
        }
    }
}
