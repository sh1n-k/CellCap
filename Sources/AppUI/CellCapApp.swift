import Core
import Shared
import SwiftUI

@main
struct CellCapApp: App {
    @StateObject private var viewModel: MenuBarViewModel

    init() {
        _viewModel = StateObject(wrappedValue: .previewHolding())
    }

    var body: some Scene {
        MenuBarExtra {
            RootView(viewModel: viewModel)
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsSceneView(viewModel: viewModel)
        }
    }
}
