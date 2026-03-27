import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusSummaryView(viewModel: viewModel)
                PolicySettingsView(viewModel: viewModel, compact: true)
                CapabilityStatusListView(viewModel: viewModel)

                HStack(spacing: 10) {
                    SettingsLink {
                        Label("설정 화면", systemImage: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.76))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.74))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        viewModel.recomputeState()
                    } label: {
                        Label("상태 다시 계산", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.88, green: 0.53, blue: 0.21))
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
