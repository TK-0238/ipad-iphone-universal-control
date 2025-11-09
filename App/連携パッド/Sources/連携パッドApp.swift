import SwiftUI
import SharedControlKit
import SidecarCastingKit

@main
struct 連携パッドApp: App {
    @StateObject private var viewModel = AppSessionViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(viewModel)
        }
    }
}
