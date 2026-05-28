import SwiftUI

struct RootView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var isAdvancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CellCapTheme.Spacing.section) {
                StatusSummaryView(viewModel: viewModel)
                PolicySettingsView(viewModel: viewModel)
                AdvancedStatusSectionView(
                    viewModel: viewModel,
                    isExpanded: $isAdvancedExpanded
                )
                footerActions
            }
            .padding(CellCapTheme.Spacing.popoverPadding)
        }
        .frame(width: 396, height: 560)
        .background(CellCapPanelBackground())
        .onAppear {
            isAdvancedExpanded = viewModel.shouldAutoExpandAdvancedSection
        }
        .onChange(of: viewModel.shouldAutoExpandAdvancedSection) { _, shouldExpand in
            if shouldExpand {
                isAdvancedExpanded = true
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.recomputeState()
            } label: {
                Label("상태 다시 계산", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityHint("앱 상태와 helper 연결을 다시 동기화합니다")

            Button {
                viewModel.prepareDiagnosticsExport()
            } label: {
                Label("진단 내보내기", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityHint("최근 진단 요약을 내보냅니다")

            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

#Preview("메뉴 막대 - 제한 유지") {
    RootView(viewModel: .previewHolding())
}

#Preview("메뉴 막대 - 오류") {
    RootView(viewModel: .previewErrorReadOnly())
}
