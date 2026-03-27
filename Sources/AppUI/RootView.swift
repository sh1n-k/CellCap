import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusSummaryView(viewModel: viewModel)
                PolicySettingsView(viewModel: viewModel)
                CapabilityStatusListView(viewModel: viewModel)

                HStack {
                    Button {
                        viewModel.recomputeState()
                    } label: {
                        Label("상태 다시 계산", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.88, green: 0.53, blue: 0.21))

                    Spacer(minLength: 0)
                }
            }
            .padding(18)
        }
        .frame(width: 396, height: 560)
        .background(CellCapPanelBackground())
    }
}

#Preview("메뉴 막대 - 제한 유지") {
    RootView(viewModel: .previewHolding())
}

#Preview("메뉴 막대 - 오류") {
    RootView(viewModel: .previewErrorReadOnly())
}
