import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.menuBarSymbolName)
                .imageScale(.medium)
                .accessibilityHidden(true)

            Text(viewModel.batteryPercentText)
                .monospacedDigit()
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.menuBarAccessibilityLabel)
    }
}

#Preview("Menu Bar Label") {
    MenuBarLabelView(viewModel: .previewHolding())
        .padding()
}
